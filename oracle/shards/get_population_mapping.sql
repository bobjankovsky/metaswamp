create or replace function get_population_mapping(
  p_source_name  varchar2          -- source table or view name
,p_target_name  varchar2          -- target table or view name
,p_source_owner varchar2 := USER  -- source owner (default USER)
,p_target_owner varchar2 := USER  -- target owner (default USER)
) return CLOB is 
--flags for auxiliary columns
   c_valid_to_flag    Varchar2(50 CHAR):='ColScdToFlag';             -- flag of VALID TO column for SCD record history type
   c_valid_from_flag  Varchar2(50 CHAR):='ColScdFromFlag';           -- flag of VALID FROM column for SCD record history type
   c_eff_date_flag    Varchar2(50 CHAR):='ColSnapDateFlag';          -- flag of EFF_DATE column for SNAP history type
   c_deleted_flag     Varchar2(50 CHAR):='ColDeletedFlag';           -- flag of deleted flag for SOFT DELETE approach
   c_ins_dt_flag      Varchar2(50 CHAR):='ColInsDtFlag';             -- flag of insert timestamp 
   c_upd_dt_flag      Varchar2(50 CHAR):='ColUpdDtFlag';             -- flag of update timestamp
   c_seq_key_flag     Varchar2(50 CHAR):='ColSeqKeyFlag';            -- flag of sequential key
--definition
   c_auxiliary_detect Varchar2(4000 CHAR):='{
     "'||c_valid_to_flag||'"    :"VALID_TO$"
    ,"'||c_valid_from_flag||'"  :"VALID_FROM$"
    ,"'||c_eff_date_flag||'"    :"^EFF_DATE$"
    ,"'||c_deleted_flag||'"     :"DELETED_FLAG$"
    ,"'||c_ins_dt_flag||'"      :"INSERTED_DATETIME$"
    ,"'||c_upd_dt_flag||'"      :"UPDATED_DATETIME$"
    ,"'||c_seq_key_flag||'"     :"_KEY$"
   }'; 
--derrived flag
   c_diffhash_flag     Varchar2(50 CHAR):='ColDiffHashFlag';        -- flag of columns relevant to comparison of record difference
   c_logical_key_flag  Varchar2(50 CHAR):='ColScdKeyFlag';       -- flag of logical key (auxiliary history columns are omited
   c_key_flag          Varchar2(50 CHAR):='ColKeyFlag';              -- flag of relevant (natural) key
   c_ins_flag          Varchar2(50 CHAR):='ColInsFlag';              -- flag of columns that should be inserted into new record 
   c_upd_flag          Varchar2(50 CHAR):='ColUpdFlag';              -- flag of columns that should be updated when we modify a record
--elements on the entity (mapping) level
   c_target_name      Varchar2(50 CHAR):='TargetName';               -- target table name 
   c_target_owner     Varchar2(50 CHAR):='TargetSchema';             -- target table owner
   c_source_name      Varchar2(50 CHAR):='SourceName';               -- source table/view name 
   c_source_owner     Varchar2(50 CHAR):='SourceSchema';             -- source table/view owner
   c_cols             Varchar2(50 CHAR):='cols';                     -- column related elements follow
--elements on the column level
   c_target_col_name      Varchar2(50 CHAR):='ColTargetName';        -- targer column name 
   c_source_col_expr      Varchar2(50 CHAR):='ColSourceExpr';        -- source column name 
   c_target_col_mandatory Varchar2(50 CHAR):='ColMandatoryFlag';     -- target column mandatory flag
   c_target_col_datatype  Varchar2(50 CHAR):='ColDataType';          -- target column datatype
--derrived elements on the entity level
   c_relevant_key      Varchar2(50 CHAR):='TargetKeyName';           -- relevant key name
   c_scd_partition_by  Varchar2(50 CHAR):='ScdPartitionBy';          -- for the SCD pattern - partition by clause
   c_scd_order_by      Varchar2(50 CHAR):='ScdOrderBy';              -- for the SCD pattern - order by clause
--defaults
   c_max_date          Varchar2(50 CHAR):='date''3000-01-01''';      -- max date for SCD VALID TO      
--control
   v_include  Boolean;   
--jsons
   v_obj  json_object_t;
   v_arr  json_array_t;
   v_col  json_object_t;
   v_def      json_object_t := json_object_t(c_auxiliary_detect); -- definition of auxiliary columns
   v_def_keys json_key_list := v_def.get_keys;                    -- list of auxiliary flags
--result
   v_res               CLOB;               
--isflag
   function is_flag(p_flag varchar2) return boolean is
   begin
     return v_col.get(p_flag).to_string = '"Y"';
   exception
     when others then return false;  
   end is_flag;     
begin 
  for r_col in (
    with ColTrg as( -- target columns
      select c.COLUMN_ID, c.COLUMN_NAME
       ,c.DATA_TYPE
        ||case 
           when c.DATA_TYPE not like 'TIMESTAMP%' and c.DATA_SCALE is not null then '('||nvl(to_char(c.DATA_PRECISION),'*')||','||to_char(c.DATA_SCALE)||')'
           when c.DATA_PRECISION is not null then '('||to_char(c.DATA_PRECISION)||')'
           when c.CHAR_LENGTH  > 0 then '('||to_char(c.CHAR_LENGTH)||case c.CHAR_USED when 'B' then ' BYTE' else ' CHAR' end||')'   
          end
        as DATA_TYPE
       ,translate(c.NULLABLE,'YN','NY') as MANDATORY_FLAG
       from ALL_TAB_COLUMNS c
      where c.TABLE_NAME = p_target_name
        and c.OWNER =  p_target_owner
    )
    , ColSrc as(  -- source columns
      select c.COLUMN_NAME 
        from ALL_TAB_COLUMNS c
       where c.TABLE_NAME = p_source_name
         and c.OWNER =  p_source_owner
    )
    , UKeys as( -- UK columns
      select  i.INDEX_NAME, ic.COLUMN_NAME
       ,count(case when (t.COLUMN_NAME is null or s.COLUMN_NAME is null) and ic.COLUMN_NAME != 'VALID_TO' then 1 end)over(partition by i.INDEX_NAME) as unelig
       ,rank() over(order by i.LEAF_BLOCKS, i.INDEX_NAME) as rn
        from ALL_INDEXES i
        join ALL_IND_COLUMNS ic on ic.INDEX_OWNER = i.OWNER and ic.INDEX_NAME = i.INDEX_NAME
        left join ColTrg t on t.COLUMN_NAME in ic.COLUMN_NAME
        left join ColSrc s on s.COLUMN_NAME in ic.COLUMN_NAME 
       where i.TABLE_OWNER = p_target_owner
         and i.TABLE_NAME = p_target_name
         and i.UNIQUENESS = 'UNIQUE'
       order by ic.COLUMN_POSITION
    )
    Select 
      ColTrg.COLUMN_NAME     as ColTargetName   
     ,ColSrc.COLUMN_NAME     as ColSourceExpr   
     ,ColTrg.MANDATORY_FLAG  as ColMandatoryFlag
     ,ColTrg.DATA_TYPE       as ColDataType
     ,nvl2(UKeys.rn,'Y','N') as ColKeyFlag
     ,max(UKeys.INDEX_NAME)over(partition by 1) as TargetKeyName
      from ColTrg 
      left join ColSrc
        on ColSrc.COLUMN_NAME = ColTrg.COLUMN_NAME 
      left join UKeys  
        on UKeys.COLUMN_NAME = ColTrg.COLUMN_NAME 
       and UKeys.unelig = 0 and UKeys.rn=1 
   ) loop
      v_include := true;
      if v_obj is null then 
        v_obj:= json_object_t();
        v_obj.put(c_target_name,  p_target_name);
        v_obj.put(c_target_owner, p_target_owner);
        v_obj.put(c_source_name,  p_source_name);
        v_obj.put(c_source_owner, p_source_owner );
        v_obj.put(c_relevant_key, r_col.TargetKeyName);
        v_arr:= json_array_t();
      end if;  
      v_col := json_object_t();
      v_col.put(c_source_col_expr,      r_col.ColSourceExpr);
      v_col.put(c_target_col_name,      r_col.ColTargetName);
      v_col.put(c_target_col_mandatory, r_col.ColMandatoryFlag);
      v_col.put(c_target_col_datatype,  r_col.ColDataType);
      v_col.put(c_key_flag,             r_col.ColKeyFlag);
      --
      for k in 1..v_def_keys.count loop  -- for each key of the definition 
        v_col.put(v_def_keys(k), case when regexp_like(r_col.ColTargetName, v_def.get_string(v_def_keys(k))) then 'Y' else 'N' end);                         
      end loop;
      -- derrived values 
      if    is_flag(c_valid_to_flag) or is_flag(c_valid_from_flag) or is_flag(c_upd_dt_flag) or is_flag(c_eff_date_flag) then
         v_col.put(c_diffhash_flag,'N');     -- first group of specific attributes out of diffhash                       
         v_col.put(c_ins_flag,'Y');                         
         v_col.put(c_upd_flag,'Y');                         
         v_col.put(c_logical_key_flag,'N'); 
      elsif is_flag(c_ins_dt_flag) or is_flag(c_seq_key_flag) then 
         v_col.put(c_diffhash_flag,'N');    -- second group of specific attributes  out of diffhash - insert only                         
         v_col.put(c_ins_flag,'Y');                         
         v_col.put(c_upd_flag,'N');                         
         v_col.put(c_logical_key_flag,'N'); 
      elsif is_flag(c_key_flag) then
         v_col.put(c_logical_key_flag,'Y'); -- logical key flag
         v_col.put(c_diffhash_flag,'N');                         
         v_col.put(c_ins_flag,'Y');                         
         v_col.put(c_upd_flag,'N');                         
      elsif r_col.ColSourceExpr is not null or is_flag(c_deleted_flag)then 
         v_col.put(c_diffhash_flag,'Y');  -- source expression is specified                       
         v_col.put(c_ins_flag,'Y');                         
         v_col.put(c_upd_flag,'Y');                         
         v_col.put(c_logical_key_flag,'N'); 
      else
         v_include := false;
      end if;
      if v_include then 
        if is_flag(c_valid_to_flag) then 
           v_col.put(c_source_col_expr, c_max_date);
        end if;
        if is_flag(c_upd_dt_flag) or is_flag(c_ins_dt_flag) then 
           v_col.put(c_source_col_expr, 'sysdate');          
        end if;
        --
        v_arr.append(v_col);
      end if;  
   end loop;
   v_obj.put(c_cols, v_arr);
   return v_obj.to_clob();
end get_population_mapping;
/
