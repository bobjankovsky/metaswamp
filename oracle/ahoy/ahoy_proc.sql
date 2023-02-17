create or replace package AHOY_PROC as
--AdHOc Yield processor
--------------------------------------------------------
  procedure threadAsync( --run thread asynchronously
    p_space varchar2:=null -- optional parameter of a space not to mess up with other users 
 );
---------------------------------------------internal--
  procedure thread( -- internal method of processing particular threads
     p_job_name varchar2  -- job name
   , p_space varchar2     -- optional parameter of a space not to mess up with other users 
  );
--------------------------------------------------------
end AHOY_PROC;
/
create or replace package body AHOY_PROC as
--AdHOc Yield processor
  c_package_name  varchar2(100) := 'AHOY_PROC';
  c_thread_prefix varchar2(100) := 'AHOY_JOB_';
--------------------------------------------------------
  procedure threadAsync (p_space varchar2:=null) is    -- methods sterts one thread asynchronously and lets it work all the remaining tasks
    v_name varchar2(100);
  begin
    v_name := c_thread_prefix||to_char(AHOY_SEQ.NEXTVAL);  -- decide the name of new one incrementing the thread number
    DBMS_SCHEDULER.CREATE_JOB(job_name => v_name, job_type => 'PLSQL_BLOCK', job_action => 'begin '||c_package_name||'.thread('''|| v_name ||''','''|| p_space ||''');end;', number_of_arguments => 0, start_date => sysdate) ; --create
    DBMS_SCHEDULER.ENABLE(v_name) ;                                                                                                                                                                         --enable
    commit;
  end threadAsync;
--------------------------------------------------------
  procedure thread(p_job_name varchar2, p_space varchar2) is  -- all these threads are homogenous, they do all tasks about dispatching and running particular jobs
     v_ataskKey   integer;    -- surrogate key of active task
     v_ataskCmd   clob;       -- buffer for the text of command 
     v_ataskCnt   integer;    -- number of identified tasks
     v_ataskBat   integer;    -- number if the following batch
     v_err        clob;       -- buffer for am error information
     v_maxThreads integer;    -- max threads parameter
     v_curThreads integer;    -- currently running threads
  begin
    loop
      --SEEK THE TASK and CHECK ORPHANS
      execute immediate 'lock table AHOY_PAR partition for ('''||p_space||''') in exclusive mode'; --lock for task manipulation (dummy lock on auxiliary table just to avoid two threads gathering the same task)
      with L1 as(
         select A.ATASK_KEY, A.ATASK_CMD, row_number()over(order by A.ATASK_KEY) rn, count(1)over(partition by A.ATASK_STATE) cnt
         from AHOY_TASK A
         left join USER_SCHEDULER_JOBS  J on J.job_name = A.ATASK_JOB and J.job_name != p_job_name  -- antijoin, check orphans. Orphans are unfinished tasks caused by a forced drop of jobs rather than by an internal error.
         where '$'||p_space = '$'||a.ATASK_SPACE-- the space reduction
           and (a.ATASK_STATE = 'TBD' or (a.ATASK_STATE = 'RUN' and J.job_name is null and systimestamp-a.atask_start>interval '10'second)) --for the state RUN with no job related it behaves like if it was TBD.
        )
        select ATASK_KEY, ATASK_CMD, cnt into v_ataskKey, v_ataskCmd, v_ataskCnt from L1 where rn=1;  -- just for the first eligible task
      update  AHOY_TASK set ATASK_STATE = 'RUN', ATASK_JOB = p_job_name, ATASK_START = systimestamp where ATASK_KEY=v_ataskKey; -- notify the task is to be started
      commit; --unlocks the task seeking process for other threads, this one is booked by current thread by the update
      --WAKE UP COWORKERS
      begin
         select APAR_THREADS into v_maxThreads from AHOY_PAR where '$'||APAR_SPACE='$'||p_space;  --get maximum number of threads from the parameter table. It should be done again because it could be changed from outside to stop, reduce, or increase number of threads
      exception
         when NO_DATA_FOUND then    
           v_maxThreads:=5; -- default
           insert into AHOY_PAR(APAR_SPACE,APAR_THREADS)values(p_space,v_maxThreads);
      end;
      --select count(1) into v_curThreads from USER_SCHEDULER_JOBS where regexp_like(job_name,'^'||c_thread_prefix || '\d+$');  -- get number of currently running threads
      select count(1) into v_curThreads from AHOY_TASK where ATASK_STATE='RUN' and '$'||ATASK_SPACE='$'||p_space;  -- get number of currently running threads by number of running tasks
      if v_ataskCnt > 1 and v_maxThreads > v_curThreads then  -- if current number of threads is less than the maximum one and there are more tasks waiting
        threadAsync(p_space);  -- it starts another thread - just one, the process will recure with the new thread if necessary
      end if;
      --PROCESSING
      begin --inner fault processing
        execute immediate v_ataskCmd;  -- dynamic run of the command
        update  AHOY_TASK set ATASK_STATE = 'OK', ATASK_END = systimestamp where ATASK_KEY=v_ataskKey; -- check as OK after successful finish
        commit;  -- outside commit, the best practice is not to commit transactions within tasks themselves, just keep them intra-transaction
      exception
        when others then  -- any error will be documented
          v_err := SQLERRM;
          update  AHOY_TASK set ATASK_STATE = 'ERR', ATASK_END = systimestamp, ATASK_MSG = v_err where ATASK_KEY=v_ataskKey; -- here
          commit;
      end; --/inner fault processing
      --- ASLEEP
      select count(1) into v_curThreads from AHOY_TASK where ATASK_STATE='RUN' and '$'||ATASK_SPACE='$'||p_space;  -- get number of currently running threads by number of running tasks
      if v_maxThreads <= v_curThreads then
        raise NO_DATA_FOUND;  --end loop, job
      end if;
    end loop;
  exception
    when NO_DATA_FOUND then -- expected exit, no data to process, check for another batch 
       select count(1)      -- all the following section is about processing of several batches in order
       into v_ataskCnt
       from AHOY_TASK A 
       where A.ATASK_STATE in ('ERR','RUN','TBD')
         and '$'||ATASK_SPACE='$'||p_space; --checks there are no remaining tasks from previous batches
       if v_ataskCnt = 0 then -- so when they are not
         select min(to_number(regexp_substr(A.ATASK_STATE,'\d+')))  
         into v_ataskBat
         from AHOY_TASK A 
         where ATASK_STATE like 'BAT%'
           and '$'||ATASK_SPACE='$'||p_space; -- find the first following batch (BAT1, BAT2 ...)
         if v_ataskBat is not null then -- and if there is any
            Update AHOY_TASK set ATASK_STATE='TBD' where to_number(regexp_substr(ATASK_STATE,'\d+'))=v_ataskBat and ATASK_STATE like 'BAT%' and '$'||ATASK_SPACE='$'||p_space; --just switch it to TBD
            threadAsync(p_space); -- and because your thread is just finishing, start new one
         end if; 
       end if;
    when others then --unexpected errors will be documented in the parameter table AHOY_PAR
      v_err := SQLERRM;
      update  AHOY_PAR set APAR_LAST_ERR = v_err;
      commit; 
  end thread;
end AHOY_PROC;
/