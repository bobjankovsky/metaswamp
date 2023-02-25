create or replace function treat_template(
   p_metadata varchar  -- metadata of the generated code
  ,p_template varchar  -- template of the generation pattern 
) returns varchar as
$$
declare -- a generic function for using templates based on json parametrization
  v_stmt varchar := replace(p_template, '\n', E'\n'); -- processed statement in progress
  v_metadata jsonb:= p_metadata::jsonb;               -- json object of parameters
  r_elem     record;                                  -- record of an element
  --do array variables
  r_arr      record;               -- record of array instances 
  v_delim    varchar(4000);        -- delimiter from the template
  v_cond     varchar(100);         -- condition attribute from the template
  v_mask     varchar;              -- inner part of the mask
  --do join variables
  v_joinres  varchar;              -- processed value in progress
  v_true     char;                 -- the true value of the condition flag (N for negations)  
  v_del      varchar(4000);        -- current delimiter
  r_arrelem  record;               -- elements of the array to be joined     
  v_is       boolean;              -- result of condition in conditioned arrays
begin 
  for r_elem in (select * from jsonb_each(v_metadata)) loop -- loop over all elements of metadata
    if jsonb_typeof(r_elem.value) = 'array' then       
	  --do_array
      for r_arr in (select t[1] as lmask, t[2] as content from regexp_matches(v_stmt,format('(\{%s\:\[([^]]*)\]\})',r_elem.key),'g') t) loop
		v_delim := regexp_substr(r_arr.content,'^([^|]+)\|',1,1,'i',1); 
		v_cond  := regexp_substr(r_arr.content,'\?([^?]+)$',1,1,'i',1); 
		v_mask  := regexp_replace(r_arr.content,'\?[^?]+$','');
		v_mask  := regexp_replace(v_mask,'^[^|]+\|','');
		--do_join 
		v_joinres := '';
        if v_cond is not null and v_cond ^@ '!' then   -- treat negation in conditions
           v_cond := substr(v_cond,2);
           v_true := 'N'; 
		else   
		   v_true := 'Y';
        end if;  
        if v_delim ^@ E'\n' and length(v_delim) > 1 then  -- in the case delimiter starts with \n, we align the first row
          v_del := lpad(' ', length(v_delim)-1,' ');
        else
		  v_del := '';
        end if; 
        for r_arrelem in (select jsonb_array_elements(r_elem.value) as t) loop  --jsonb array
          if v_cond is not null and v_cond != '' then         -- condition if specified to v_is 
            v_is := (r_arrelem.t ->> v_cond = v_true); 
          else 
		    v_is := true;
          end if;		  
          if v_is then 
            v_joinres := v_joinres || v_del || treat_template(r_arrelem.t::varchar ,v_mask);  -- recursive template processing for each member
            v_del := v_delim;                                                                   -- delim for each other column
		  end if;
        end loop;
		--/do_join
		v_stmt := replace(v_stmt, r_arr.lmask, v_joinres); 
      end loop;		
      --/do_array
    elsif jsonb_typeof(r_elem.value) = 'string' then       -- or standard string
       v_stmt := replace(v_stmt, '{'||r_elem.key||'}',(r_elem.value) #>> '{}'); -- the only place atomic elements are replaced
    end if;
  end loop;
  return v_stmt;
end;
$$ language plpgsql;
