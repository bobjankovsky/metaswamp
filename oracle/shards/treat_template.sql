function treat_template(
   p_metadata clob  -- metadata of the generated code
  ,p_template clob  -- template of the generation pattern 
) return clob is
-- a generic function for using templates based on json parametrization
  v_jobj     json_object_t := json_object_t(p_metadata); -- json object of parameters
  v_keys     json_key_list := v_jobj.get_keys;         -- list of keys in parameters
  v_key      varchar2(100 char);                       -- particular key in the process
  v_elem     json_element_t;                           -- particular element in the process
  v_stmt     clob := replace(p_template, '\n', chr(10)); -- processed statement in progress
  -- following function manages processing of particular members of arrays
  function  do_join(p_delim varchar2, p_mask varchar2, p_cond varchar2, p_array json_array_t) return clob is
    v_res  clob;                                       -- processed value in progress
    v_size Integer := p_array.get_size;                -- size of the array
    v_del  varchar2(4000 char):='';                    -- current delimiter
    v_is   boolean := true;                            -- result of condition in conditioned arrays
    v_cond varchar2(100 char):= trim(p_cond);          -- the condition
    v_true char(3 char) := '"Y"';                      -- the true value of the condition flag (N for negations)  
    v_val  json_element_t;                             -- buffer for the condition value                           
  begin
    if v_cond is not null and substr(v_cond,1,1)='!' then   -- treat negation in conditions
       v_cond := substr(v_cond,2);
       v_true := '"N"'; 
    end if;  
    if substr(p_delim,1,1) = chr(10) and length(p_delim) > 1 then  -- in the case delimiter starts with \n, we align the first row
      v_del := lpad(' ', length(p_delim)-1,' ');
    end if;  
    for i in 0..v_size-1 loop            -- for each member of array
      if v_cond is not null then         -- condition if specified to v_is 
        v_val := treat(p_array.get(i) as json_object_t).get(v_cond);
        if v_val is not null then 
          v_is := (v_val.to_string = v_true);
        else 
          v_is := false;  
        end if;   
      end if;  
      if p_array.get(i).is_object and v_is then                                     -- process objects in template only
        v_res := v_res || v_del || treat_template(p_array.get(i).to_clob ,p_mask);  -- recursive template processing for each member
        v_del := p_delim;                                                           -- delim for each other column
      end if;  
    end loop;
    return v_res;
  end;
  -- following procedure prepares array for processing
  procedure do_array is
    v_lmask    varchar2(4000 char);  -- local mask of array usage
    v_lmlen    integer;              -- length of the mask  
    v_subst    clob;                 -- substitution text in progress
    v_icnt     integer;              -- count of instances of particular array in the template 
    v_delim    varchar2(4000 char);  -- delimiter from the template
    v_cond     varchar2(100  char);  -- condition attribute from the template
  begin
    v_icnt  := regexp_count(v_stmt, '\{'||v_key||'[:}]');
    for i in 1..v_icnt loop
      v_lmask := regexp_substr(v_stmt, '\{'||v_key||'((:\[)([^]]*)(\]))?\}', 1, 1, 'ni', 3); -- extraction of the mask from template
      v_lmlen := nvl(length(v_lmask),-3)+3;                          -- length to be substitued, 3 additional characters are ':[]', not for present null values
      v_delim := regexp_substr(v_lmask,'^([^|]*)\|', 1, 1, 'ni',1);  -- extraction of the delimiter
      v_lmask := regexp_replace(v_lmask,'^[^|]*\|','', 1, 1, 'ni');  -- removal of the delimiter from mask
      v_cond  := regexp_substr(v_lmask,'\?(.*)$', 1, 1, 'ni',1);     -- extraction of the condition
      v_lmask := regexp_replace(v_lmask,'\?.*$','', 1, 1, 'ni');     -- removal of the condition from mask 
      v_subst := do_join(v_delim, v_lmask, v_cond, v_jobj.get_array(v_key)); --processing of the array substitution instance 
      v_stmt := regexp_replace(v_stmt, '\{'||v_key||'.{'||to_char(v_lmlen)||'}\}',v_subst,1,1,'ni'); -- substitution
    end loop;
  end do_array;
begin
  for i in 1 .. v_keys.count loop     -- loop over all keys in metadata
    v_key  := v_keys(i);              -- key
    v_elem := v_jobj.get(v_keys(i));  -- element
    if v_elem.is_array then           -- is either an array
       do_array;
    elsif v_elem.is_string then       -- or standard string
       v_stmt := replace(v_stmt, '{'||v_key||'}',trim('"' from v_elem.to_string)); -- the only place atomic elements are replaced
    end if;
  end loop;
  return v_stmt;
end treat_template;
