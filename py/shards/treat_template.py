import json
import re
def treat_template(p_metadata, p_template):
    metadata = json.loads(p_metadata)
    stmt = p_template
    for item in metadata.items():
        if type(item[1]) == str:
            stmt = stmt.replace("{{{}}}".format(item[0]),item[1]) #the only place atomic elements are replaced
        elif type(item[1]) == list:
            for instance in re.findall('\{{{}\:\[[^]]*\]\}}'.format(item[0]), stmt):
                arrdef = re.sub('(^[^[]+\[)|(\]\}$)',"",instance)
                (delim,itemcorefilter) = arrdef.split('|',1)
                itemcoresplit = itemcorefilter.rsplit('?',1)
                itemcore = itemcoresplit[0]
                if len(itemcoresplit) == 2:                     #the list is filtered
                    if itemcoresplit[1][0] == "!":
                        flag = itemcoresplit[1][1:]
                        yes = "N"
                    else:
                        flag = itemcoresplit[1]
                        yes = "Y"
                    listresult = delim.join([treat_template(str(listitem).replace("'",'"'),itemcore) for listitem in item[1] if (listitem[flag] == yes)])
                else:
                    listresult = delim.join([treat_template(str(listitem).replace("'",'"'),itemcore) for listitem in item[1]])
                if delim[0] == '\n':
                    listresult = (" " * (len(delim)-1)) + listresult
                stmt = re.sub(re.escape(instance),listresult,stmt)
    return stmt

