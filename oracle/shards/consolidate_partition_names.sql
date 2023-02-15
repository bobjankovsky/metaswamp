procedure consolidate_partition_names(
   p_table_mask  in varchar2 := '%'       -- mask of processed tables
  ,p_table_owner in varchar2 := USER      -- owner 
) is
  v_highvalue   varchar2(32676 BYTE);     --buffer for high value
  v_highdate    date;                     --buffer for high date
  v_int_lower   integer;                  --lower limit of integer interval
  v_int_upper   integer;                  --upper limit of integer interval
  v_newname     varchar2(100 CHAR);       --new name of the partition
  v_stmt        varchar2(32676 BYTE);     --the statement
begin
  for r1 in(  -- All tables of the schema with interval partitioning
   select
       pt.TABLE_NAME
      ,Case  -- Pattern identification
        when pkc.COLUMN_NAME like '%TIME_KEY' then 'TIME_KEY' -- Julian calendar transformation (RB ETL)
        when upper(pt.INTERVAL) like '%INTERVAL%MINUTE%' then 'MINUTE'    --Minutes YYYYMMDDHH24MI
        when upper(pt.INTERVAL) like '%INTERVAL%HOUR%'   then 'HOUR'      --Hours  YYYYMMDDHH24
        when upper(pt.INTERVAL) like '%INTERVAL%DAY%'    then 'DATE'      --Treated as DATE YYYYMMDD
        when upper(pt.INTERVAL) like '%INTERVAL%MONTH%'  then 'DATE'      --Treated as DATE YYYYMMDD
        when upper(pt.INTERVAL) like '%INTERVAL%YEAR%'   then 'YEAR'      --YYYY
        when trim(pt.INTERVAL) = '1'                     then 'INT1'      --integer value 1
        when regexp_like(pt.INTERVAL,'^\d+$')            then 'INT'       --integer value (FM)
        when pt.AUTOLIST = 'YES'                         then 'LIST'      --autolist value
      end as PATTERN
     ,pt.INTERVAL
    from ALL_PART_TABLES pt
    join ALL_PART_KEY_COLUMNS pkc
      on pkc.NAME = pt.TABLE_NAME
     and pkc.OWNER = p_table_owner
   where (pt.INTERVAL is not null or pt.AUTOLIST = 'YES' )  -- indicates interval partitioning
     and pt.OWNER = p_table_owner
     and pt.TABLE_NAME like p_table_mask
  ) loop
    for r2 in (  -- All partitions with initial naming
      select p.PARTITION_NAME
        from ALL_TAB_PARTITIONS p
       where p.TABLE_NAME = r1.TABLE_NAME
         and p.TABLE_OWNER = p_table_owner
         and ( p.PARTITION_NAME like 'SYS%') -- system initial naming of the partition
    ) loop
      select p.HIGH_VALUE  -- datatype is long, that is why we do it this way of transformation into varchar2
        into v_highvalue   -- literal information of the high value
        from ALL_TAB_PARTITIONS p
       where p.TABLE_NAME = r1.TABLE_NAME
         and p.TABLE_OWNER = p_table_owner
         and p.PARTITION_NAME=r2.PARTITION_NAME;
      if r1.PATTERN = 'TIME_KEY' then -- this is the RB ETL trick coding day based date as an integer through Julian calendar notation
         execute immediate 'select to_date('''||v_highvalue||''',''j'') from dual' into v_highdate;
      elsif r1.PATTERN in ('HOUR','MINUTE','DATE','YEAR') or  r1.PATTERN = 'LIST' and regexp_like(v_highvalue,'^TO_DATE')  then -- all other date patterns
         execute immediate 'select '||v_highvalue||' from dual' into v_highdate;
      elsif r1.PATTERN in ('INT1','INT') then  -- integers
         v_int_upper := to_number(v_highvalue)-1;
         if r1.PATTERN = 'INT' then  -- integers bigger than one
           v_int_lower := to_number(v_highvalue)-to_number(r1.INTERVAL);
         end if;
      end if;
      if r1.PATTERN = 'INT' then
        v_newname := 'PARTITION_'||to_char(v_int_lower)||'_'||to_char(v_int_upper);
      elsif r1.PATTERN = 'INT1' then
        v_newname := 'PARTITION_'||to_char(v_int_upper);
      elsif  r1.PATTERN in ('TIME_KEY','DATE') then
        v_newname := 'PARTITION_'||to_char(v_highdate-1,'YYYYMMDD');
      elsif  r1.PATTERN = 'HOUR' then
        v_newname := 'PARTITION_'||to_char(v_highdate-1/24,'YYYYMMDDHH24');
      elsif  r1.PATTERN = 'MINUTE' then
        v_newname := 'PARTITION_'||to_char(v_highdate-1/24/60,'YYYYMMDDHH24MI');
      elsif  r1.PATTERN = 'YEAR' then
        v_newname := 'PARTITION_'||to_char(v_highdate-1,'YYYY');
      elsif  r1.PATTERN = 'LIST' and regexp_like(v_highvalue,'^\d+$')  then  --numeric lists
        v_newname := 'PARTITION_'||v_highvalue;
      elsif  r1.PATTERN = 'LIST' and regexp_like(v_highvalue,'^''\w+''$')  then  --string lists
        v_newname := 'PARTITION_'||replace(v_highvalue,'''');
      elsif  r1.PATTERN = 'LIST' and regexp_like(v_highvalue,'^TO_DATE')  then  --date lists
        v_newname := 'PARTITION_'||regexp_replace(to_char(v_highdate,'YYYYMMDDHH24MISS'),'(0{2}){0,3}$'); -- reacts to real precision of the value
      else
        v_newname := null;
      end if;
      if v_newname is not null then
         begin
           v_stmt:='alter table '||p_table_owner||'.'||r1.TABLE_NAME
             ||' rename partition '||r2.PARTITION_NAME||' to '||v_newname;
           execute immediate v_stmt;
         exception
           when others then
            DBMS_OUTPUT.PUT_LINE(v_stmt);
         end;
      end if;
    end loop; --r2
  end loop; --r1
end consolidate_partition_names;
