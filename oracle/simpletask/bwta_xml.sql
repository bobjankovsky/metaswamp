----------------------------------------------------------------------
-- PACKAGE BWTA_XML                                                 --
----------------------------------------------------------------------
Create or replace PACKAGE BWTA_XML AS 
  ----------------------------------------------------------------------------- 
  --Purpose: Simple processes and task management  / XML import / export     -- 
  --Author:  Bob Jankovsky, copyleft 2008, 2013                              -- 
  --History: 1.0 /21-AUG-2013 -- AddOn to BWTA SIMPLETASK                    -- 
  ------------------------------------------------------------------------------ 
  c_schema_id constant varchar2(100):='http://bobjankovsky.org/stage/bwta_simpletask.xsd';
  ------------------------------------------------------------------------------ 
  PROCEDURE importXML( -- Imports metadata from XML
    P_XML clob           --XML import data
   ,P_TAG varchar2:=null --Override tag for change management, if omit then teh original tag in XML document is used
  );
  ------------------------------------------------------------------------------
  FUNCTION getExport( --Gets XML Export
     P_TAG       varchar2:='EXPORT_'||TO_CHAR(SYSDATE,'dd.mm.yyyy hh24:mi:ss'), --Tag of the export
     P_NOTE      varchar2:='Full export at '||TO_CHAR(SYSDATE,'dd.mm.yyyy hh24:mi:ss'), --Note of the export
     P_HEAP_MASK varchar2:='%', --mask of heaps
     P_TASK_MASK varchar2:='%', --mask of tasks
     P_RES_MASK  varchar2:='%'  --mask of resources
  ) RETURN XMLTYPE;
  ------------------------------------------------------------------------------ 
  -- Auxiliary functions for XML exporting                                    --
  ------------------------------------------------------------------------------ 
  FUNCTION getDependencies( --Gets dependency XML tag content from metadata
     P_TASK_SEQ  integer -- sequence key of the task
  ) RETURN XMLTYPE;
  ------------------------------------------------------------------------------ 
  FUNCTION getConsumptions( --Gets resource consumption XML tag content from metadata
     P_TASK_SEQ  integer -- sequence key of the task
  ) RETURN XMLTYPE;
  ------------------------------------------------------------------------------ 
  FUNCTION getTasks( --Gets dependency XML tag content from metadata
     P_HEAP_SEQ     integer, -- sequence key of the heap
     P_TASK_ID_MASK varchar2:='%' --mask of the chosen tasks
  ) RETURN XMLTYPE;
  ------------------------------------------------------------------------------
  FUNCTION getProcesses( --Gets process XML tag content from metadata
     P_HEAP_ID_MASK varchar2:='%', --mask of heap identifiers
     P_TASK_ID_MASK varchar2:='%'  --mask of task identifiers
  ) RETURN XMLTYPE;
------------------------------------------------------------------------------
  FUNCTION getResources( --Gets resource XML tag content from metadata
     P_RES_ID_MASK varchar2:='%' --mask of resource identifiers
  ) RETURN XMLTYPE;
------------------------------------------------------------------------------ 
END BWTA_XML;
/
----------------------------------------------------------------------
-- PACKAGE BODY BWTA_XML                                            --
----------------------------------------------------------------------
Create or replace PACKAGE BODY BWTA_XML AS
  TYPE TR_TASK_ID IS record (ID VARCHAR2(100),HEAP INTEGER);
  TYPE TA_TASK_ID is table of TR_TASK_ID index by binary_integer;
  ------------------------------------------------------------------------------ 
  PROCEDURE importXML( -- Imports metadata from XML
    P_XML clob           --XML import data
   ,P_TAG varchar2:=NULL --Change tag for change management, if omit then teh original is used
  ) IS
    v_xml XMLTYPE;
    v_tag VARCHAR2(100);
    v_heap_seq INTEGER;
    va_tasks TA_TASK_ID;
    vi_tasks binary_integer;
    CURSOR c_wf IS SELECT * FROM XMLTABLE 
      ( '/WORKFLOW' PASSING v_xml  
        COLUMNS 
         TAG  VARCHAR2(100) PATH '@TAG' 
      );  
    CURSOR c_res IS SELECT * FROM XMLTABLE 
      ( '/WORKFLOW/RESOURCES/RESOURCE' PASSING v_xml  
        COLUMNS 
         ID  VARCHAR2(100) PATH '@ID' 
        ,AMOUNT NUMBER PATH '@AMOUNT' 
        ,NOTE  VARCHAR2(2000) PATH '@NOTE' 
        ,TYPE  VARCHAR2(100) PATH '@TYPE' 
        ,DEL   VARCHAR2(1) PATH '@DELETE' 
      );  
    CURSOR c_heap IS SELECT * FROM XMLTABLE 
      ( '/WORKFLOW/PROCESSES/PROCESS' PASSING v_xml  
        COLUMNS 
         ID  VARCHAR2(100) PATH '@ID' 
        ,NOTE  VARCHAR2(2000) PATH '@NOTE' 
        ,ISHEAP  VARCHAR2(100) PATH '@TYPE' 
        ,DEL   VARCHAR2(1) PATH '@DELETE'
        ,TASKS XMLTYPE PATH 'TASKS'
      );  
    CURSOR c_task(p_XML XMLTYPE) IS SELECT * FROM XMLTABLE 
      ( '/TASKS/TASK' PASSING p_xml  
        COLUMNS 
         ID         VARCHAR2(100)  PATH '@ID' 
        ,NOTE       VARCHAR2(2000) PATH '@NOTE' 
        ,EXEC_COND  VARCHAR2(4000) PATH '@EXEC_COND' 
        ,SKIP_COND  VARCHAR2(4000) PATH '@SKIP_COND' 
        ,EXEC_CODE  VARCHAR2(4000) PATH '@EXEC_CODE' 
        ,EXEC_FLAG  VARCHAR2(1)    PATH '@EXEC_FLAG' 
        ,SKIP_FLAG  VARCHAR2(1)    PATH '@SKIP_FLAG' 
        ,FULL_FLAG  VARCHAR2(1)    PATH '@FULL' 
        ,PRIORITY   NUMBER         PATH '@PRIORITY' 
        ,DEL        VARCHAR2(1)    PATH '@DELETE' 
        ,PREDECESSORS  XMLTYPE     PATH 'PREDECESSORS'
        ,CONSUMPTIONS  XMLTYPE     PATH 'CONSUMPTIONS'
      );  
    CURSOR c_predecessor(p_XML XMLTYPE) IS SELECT * FROM XMLTABLE 
      ( '/PREDECESSORS/PREDECESSOR' PASSING p_xml  
        COLUMNS 
         ID         VARCHAR2(100)  PATH '@ID' 
        ,TYPE       VARCHAR2(100)  PATH '@TYPE' 
        ,HEAP       VARCHAR2(100)  PATH '@HEAP' 
        ,DEL        VARCHAR2(1)    PATH '@DELETE' 
      );  
    CURSOR c_consumption(p_XML XMLTYPE) IS SELECT * FROM XMLTABLE 
      ( '/CONSUMPTIONS/CONSUMPTION' PASSING p_xml  
        COLUMNS 
         ID         VARCHAR2(100)  PATH '@ID' 
        ,AMOUNT     NUMBER         PATH '@AMOUNT' 
        ,DEL        VARCHAR2(1)    PATH '@DELETE' 
      );  
  BEGIN
    v_XML:=XMLTYPE(P_XML);
    V_XML:=V_XML.createSchemaBasedXML(BWTA_XML.c_schema_id);
    v_XML.schemaValidate;
    --TAG preparation
    FOR r1 IN c_wf LOOP
      V_tag:=r1.tag;
    END LOOP;
    V_TAG:=NVL(P_TAG,V_TAG);
    --Resources
    FOR r1 IN c_res LOOP
      if NVL(r1.DEL,'N')='N' then 
        BWTA_METADATA.setRes(
           r1.ID
          ,r1.NOTE
          ,r1.AMOUNT
          ,CASE WHEN r1.TYPE='CUMULATIVE' THEN 1 ELSE 0 END
          ,v_tag
        );
      ELSE
        BWTA_METADATA.delRes(
           r1.ID
          ,v_tag
        );
      end if;
    END LOOP;
    FOR r1 IN c_heap LOOP
      IF NVL(r1.DEL,'N')='N' THEN 
        BWTA_METADATA.setHeap(
           r1.ID
          ,r1.NOTE
          ,v_tag
        );
        Select heap_seq into v_heap_seq from bwta_v_heap where heap_id = r1.ID;
        FOR r2 IN c_task(r1.TASKS) LOOP
          IF NVL(r2.DEL,'N')='N' THEN 
            BWTA_METADATA.setTask(
              v_heap_seq
             ,r2.ID
             ,r2.NOTE
             ,r2.EXEC_COND
             ,r2.SKIP_COND
             ,CASE WHEN r2.EXEC_FLAG='N' THEN 0 ELSE 1 END
             ,CASE WHEN r2.SKIP_FLAG='Y' THEN 1 ELSE 0 END
             ,r2.EXEC_CODE
             ,R2.PRIORITY
             ,v_tag
            );
            FOR r3 IN c_predecessor(r2.PREDECESSORS) LOOP
              IF NVL(r3.DEL,'N')='N' THEN 
                BWTA_METADATA.setTaskRel(
                  r2.ID
                 ,r3.ID
                 ,v_heap_seq
                 ,CASE WHEN r3.TYPE='NONE' THEN 1 ELSE 0 END 
                 ,v_tag
                ) ;  
              ELSE
                FOR r4 IN (
                  SELECT TASK_SEQ_1,TASK_SEQ_2 
                  FROM bwta_v_task_rel 
                  WHERE heap_seq_1=v_heap_seq
                    AND TASK_ID_1 = r2.ID 
                    AND TASK_ID_2 = r3.ID
                )LOOP
                  BWTA_METADATA.DELTASKREL(
                     R4.TASK_SEQ_1
                    ,r4.TASK_SEQ_2
                    ,v_tag
                  );
                END LOOP;  
              END IF;
            END loop;
            FOR r3 IN c_consumption(r2.CONSUMPTIONS) LOOP
              IF NVL(r3.DEL,'N')='N' THEN 
                BWTA_METADATA.setTaskRes(
                  r2.ID
                 ,V_HEAP_SEQ
                 ,R3.ID
                 ,r3.AMOUNT
                 ,v_tag
                ) ;  
              ELSE
                FOR R4 IN (
                  SELECT TASK_SEQ,RES_SEQ 
                  FROM bwta_v_task_res 
                  WHERE heap_seq=v_heap_seq
                    AND TASK_ID = R2.ID 
                    AND RES_ID = r3.ID
                )LOOP
                  BWTA_METADATA.delTaskRes(
                     R4.TASK_SEQ
                    ,r4.RES_SEQ
                    ,v_tag
                  );
                END LOOP;  
              END IF;
            END loop;
          ELSE
            BWTA_METADATA.delTask(
               r2.ID
              ,v_heap_seq 
              ,v_tag
            );
          END IF;
        END LOOP;
      ELSE 
        va_tasks.DELETE;
        SELECT TASK_ID,HEAP_SEQ BULK COLLECT INTO va_tasks FROM bwta_v_task WHERE heap_ID=r1.ID;
        vi_tasks:=va_tasks.FIRST;
        while vi_tasks IS NOT NULL LOOP
          BWTA_METADATA.delTask(
             va_tasks(vi_tasks).ID
            ,va_tasks(vi_tasks).HEAP 
            ,v_tag
          );
          vi_tasks:=va_tasks.NEXT(vi_tasks);
        END LOOP;
        BWTA_METADATA.delHeap(
           r1.ID
          ,v_tag
        );
      END IF;  
    END LOOP;
  END importXML;
  ------------------------------------------------------------------------------ 
  FUNCTION getDependencies( --Gets dependency XML tag content from metadata
     P_TASK_SEQ integer -- sequence key of the task
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
   SELECT
        XMLELEMENT(EVALNAME 'PREDECESSORS',
        XMLAGG(
        XMLELEMENT(EVALNAME 'PREDECESSOR', XMLATTRIBUTES(
          TR.TASK_ID_2 AS ID
         ,H.HEAP_ID AS HEAP
         ,DECODE(TR.SKIP_FLAG,0,'CURRENT',1,'NONE','CURRENT') AS TYPE
        )))) AS PREDECESSOR
      INTO V_XML  
      FROM BWTA_V_TASK_REL TR
      JOIN BWTA_V_HEAP H ON H.HEAP_SEQ=TR.HEAP_SEQ_2
      WHERE TR.TASK_SEQ_1 = P_TASK_SEQ;
      IF V_XML.GETSTRINGVAL() = '<PREDECESSORS></PREDECESSORS>'
      THEN 
        RETURN NULL;
      ELSE  
        RETURN V_XML;
      END IF;  
  END getDependencies;
  ------------------------------------------------------------------------------ 
  FUNCTION getConsumptions( --Gets resource consumption XML tag content from metadata
     P_TASK_SEQ integer -- sequence key of the task
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
   SELECT
        XMLELEMENT(EVALNAME 'CONSUMPTIONS',
        XMLAGG(
        XMLELEMENT(EVALNAME 'CONSUMPTION', XMLATTRIBUTES(
          TR.RES_ID AS ID
         ,TR.AMOUNT AS AMOUNT
        )))) AS PREDECESSOR
      INTO V_XML  
      FROM BWTA_V_TASK_RES TR
      WHERE TR.TASK_SEQ = P_TASK_SEQ;
      IF V_XML.GETSTRINGVAL() = '<CONSUMPTIONS></CONSUMPTIONS>'
      THEN 
        RETURN NULL;
      ELSE  
        RETURN V_XML;
      END IF;  
  END getConsumptions;
------------------------------------------------------------------------------
  FUNCTION getTasks( --Gets task XML tag content from metadata
     P_HEAP_SEQ     integer, -- sequence key of the heap
     P_TASK_ID_MASK varchar2:='%'
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
    SELECT 
       XMLELEMENT(EVALNAME 'TASKS',
       XMLAGG(
       XMLELEMENT(EVALNAME 'TASK', XMLATTRIBUTES(
         T.TASK_ID AS ID
        ,T.TASK_NOTE AS NOTE
        ,T.TASK_EXEC_COND AS EXEC_COND
        ,T.TASK_SKIP_COND AS SKIP_COND
        ,DECODE(T.TASK_EXEC_FLAG,0,'N',1,'Y','Y') AS EXEC_FLAG
        ,DECODE(T.TASK_SKIP_FLAG,0,'N',1,'Y','N') AS SKIP_FLAG
        ,T.TASK_EXEC_CODE AS EXEC_CODE
        ,T.TASK_PRIORITY AS PRIORITY
       )
        ,BWTA_XML.getDependencies(T.TASK_SEQ)
        ,BWTA_XML.getConsumptions(T.TASK_SEQ)
       ))) AS TASK
      INTO V_XML   
      FROM BWTA_V_TASK T
      WHERE T.HEAP_SEQ = P_HEAP_SEQ AND T.TASK_ID LIKE P_TASK_ID_MASK;
      IF V_XML.GETSTRINGVAL() = '<TASKS></TASKS>'
      THEN 
        RETURN NULL;
      ELSE  
        RETURN V_XML;
      END IF;  
  END getTasks;
------------------------------------------------------------------------------
  FUNCTION getProcesses( --Gets process XML tag content from metadata
     P_HEAP_ID_MASK varchar2:='%', --mask of heap identifiers
     P_TASK_ID_MASK varchar2:='%'  --mask of task identifiers
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
    SELECT 
       XMLELEMENT(EVALNAME 'PROCESSES',
       XMLAGG(
       XMLELEMENT(EVALNAME 'PROCESS', XMLATTRIBUTES(
         H.HEAP_ID AS ID
        ,H.HEAP_NOTE AS NOTE
        ,'Y' AS ISHEAP
        --,H.HEAP_ID AS HEAP_ID
       )
        ,BWTA_XML.getTasks(H.HEAP_SEQ,P_TASK_ID_MASK)
       ))) AS HEAP
      INTO V_XML   
      FROM BWTA_V_HEAP H
      WHERE HEAP_ID like P_HEAP_ID_MASK;
      IF V_XML.GETSTRINGVAL() = '<PROCESSES></PROCESSES>'
      THEN 
        RETURN NULL;
      ELSE  
        RETURN V_XML;
      END IF;  
  END getProcesses;
------------------------------------------------------------------------------
  FUNCTION getResources( --Gets resource XML tag content from metadata
     P_RES_ID_MASK varchar2:='%' --mask of resource identifiers
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
    SELECT 
       XMLELEMENT(EVALNAME 'RESOURCES',
       XMLAGG(
       XMLELEMENT(EVALNAME 'RESOURCE', XMLATTRIBUTES(
         R.RES_ID AS ID
        ,R.RES_NOTE AS NOTE
        ,R.RES_AMOUNT AS AMOUNT
        ,DECODE(R.RES_PENDING_FLAG,1,'CUMULATIVE','STANDARD') AS TYPE
       )
       ))) AS RES
      INTO V_XML   
      FROM BWTA_V_RES R WHERE RES_ID like P_RES_ID_MASK;
      IF V_XML.GETSTRINGVAL() = '<RESOURCES></RESOURCES>'
      THEN 
        RETURN NULL;
      ELSE  
        RETURN V_XML;
      END IF;  
  END getResources;
------------------------------------------------------------------------------
  FUNCTION getExport( --Gets XML Export
     P_TAG       varchar2:='EXPORT_'||TO_CHAR(SYSDATE,'dd.mm.yyyy hh24:mi:ss'), --Tag of the export
     P_NOTE      varchar2:='Full export at '||TO_CHAR(SYSDATE,'dd.mm.yyyy hh24:mi:ss'), --Note of the export
     P_HEAP_MASK varchar2:='%', --mask of heaps
     P_TASK_MASK varchar2:='%', --mask of tasks
     P_RES_MASK  varchar2:='%'  --mask of resources
  ) RETURN XMLTYPE IS
   V_XML XMLTYPE;
  BEGIN
    SELECT XMLROOT(
      XMLELEMENT(EVALNAME 'WORKFLOW', XMLATTRIBUTES(
         P_TAG AS TAG,P_NOTE AS NOTE
      ),
         BWTA_XML.getProcesses(P_HEAP_MASK,P_TASK_MASK),
         BWTA_XML.getResources(P_RES_MASK)
      )          
      ,VERSION '1.0'
    ) INTO V_XML 
    FROM DUAL;
    RETURN V_XML;
  END getExport;
------------------------------------------------------------------------------ 
  PROCEDURE registerSchema --registers schema
  IS
    v_schema varchar2(32656) := q'~
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" elementFormDefault="qualified" attributeFormDefault="unqualified">
	<xs:element name="WORKFLOW">
		<xs:annotation>
			<xs:documentation>Deployment unit of the Heap Workflow</xs:documentation>
		</xs:annotation>
		<xs:complexType>
			<xs:sequence maxOccurs="unbounded">
				<xs:element name="PROCESSES" minOccurs="0">
					<xs:complexType>
						<xs:sequence maxOccurs="unbounded">
							<xs:element name="PROCESS" type="PROCESS_TYPE" maxOccurs="unbounded"/>
						</xs:sequence>
						<xs:attribute name="FULL" type="flagType"/>
					</xs:complexType>
				</xs:element>
				<xs:element name="RESOURCES" minOccurs="0">
					<xs:complexType>
						<xs:sequence maxOccurs="unbounded">
							<xs:element name="RESOURCE" maxOccurs="unbounded">
								<xs:complexType>
									<xs:attribute name="ID" use="required"/>
									<xs:attribute name="NOTE"/>
									<xs:attribute name="TYPE" default="STANDARD">
										<xs:simpleType>
											<xs:restriction base="xs:string">
												<xs:enumeration value="STANDARD"/>
												<xs:enumeration value="CUMULATIVE"/>
											</xs:restriction>
										</xs:simpleType>
									</xs:attribute>
									<xs:attribute name="AMOUNT" type="xs:float" use="required"/>
									<xs:attribute name="DELETE" type="flagType"/>
								</xs:complexType>
							</xs:element>
						</xs:sequence>
						<xs:attribute name="FULL" type="flagType"/>
					</xs:complexType>
				</xs:element>
			</xs:sequence>
			<xs:attribute name="TAG">
				<xs:simpleType>
					<xs:restriction base="xs:string">
						<xs:maxLength value="100"/>
					</xs:restriction>
				</xs:simpleType>
			</xs:attribute>
			<xs:attribute name="NOTE" type="xs:string"/>
		</xs:complexType>
	</xs:element>
	<xs:complexType name="PREDECESSOR_TYPE">
		<xs:annotation>
			<xs:documentation>Identifies predecessor of task or process</xs:documentation>
		</xs:annotation>
		<xs:attribute name="ID" type="idType" use="required"/>
		<xs:attribute name="TYPE" default="CURRENT">
			<xs:simpleType>
				<xs:restriction base="xs:string">
					<xs:enumeration value="CURRENT"/>
					<xs:enumeration value="NONE"/>
				</xs:restriction>
			</xs:simpleType>
		</xs:attribute>
		<xs:attribute name="HEAP" type="idType"/>
		<xs:attribute name="DELETE" type="flagType"/>
	</xs:complexType>
	<xs:complexType name="CONSUMPTION_TYPE">
		<xs:annotation>
			<xs:documentation>Identifies resource and defines it's consumption by task or process</xs:documentation>
		</xs:annotation>
		<xs:attribute name="ID" use="required">
			<xs:simpleType>
				<xs:restriction base="idType">
					<xs:maxLength value="100"/>
				</xs:restriction>
			</xs:simpleType>
		</xs:attribute>
		<xs:attribute name="AMOUNT" type="xs:float" use="required"/>
		<xs:attribute name="DELETE" type="flagType"/>
	</xs:complexType>
	<xs:complexType name="PROCESS_TYPE">
		<xs:annotation>
			<xs:documentation>Specifies Heap of other hierarchical processes</xs:documentation>
		</xs:annotation>
		<xs:sequence minOccurs="0" maxOccurs="unbounded">
			<xs:element name="TASKS" minOccurs="0">
				<xs:complexType>
					<xs:sequence maxOccurs="unbounded">
						<xs:element name="TASK" maxOccurs="unbounded">
							<xs:complexType>
								<xs:sequence minOccurs="0">
									<xs:element name="PREDECESSORS" minOccurs="0">
										<xs:complexType>
											<xs:sequence maxOccurs="unbounded">
												<xs:element name="PREDECESSOR" type="PREDECESSOR_TYPE" maxOccurs="unbounded"/>
											</xs:sequence>
										</xs:complexType>
									</xs:element>
									<xs:element name="CONSUMPTIONS" minOccurs="0">
										<xs:complexType>
											<xs:sequence maxOccurs="unbounded">
												<xs:element name="CONSUMPTION" type="CONSUMPTION_TYPE" maxOccurs="unbounded"/>
											</xs:sequence>
										</xs:complexType>
									</xs:element>
								</xs:sequence>
								<xs:attribute name="ID" type="xs:string" use="required"/>
								<xs:attribute name="NOTE" type="noteType"/>
								<xs:attribute name="EXEC_COND" type="codeType"/>
								<xs:attribute name="EXEC_FLAG" type="flagType"/>
								<xs:attribute name="SKIP_COND" type="codeType"/>
								<xs:attribute name="SKIP_FLAG" type="flagType"/>
								<xs:attribute name="PRIORITY" type="xs:float"/>
								<xs:attribute name="EXEC_CODE" type="codeType" use="required"/>
								<xs:attribute name="FULL" type="flagType"/>
								<xs:attribute name="DELETE" type="flagType"/>
							</xs:complexType>
						</xs:element>
					</xs:sequence>
					<xs:attribute name="FULL" type="flagType"/>
				</xs:complexType>
			</xs:element>
		</xs:sequence>
		<xs:attribute name="ID" type="idType" use="required"/>
		<xs:attribute name="NOTE" type="noteType"/>
		<xs:attribute name="ISHEAP" type="flagType"/>
		<xs:attribute name="DELETE" type="flagType"/>
	</xs:complexType>
	<xs:simpleType name="flagType">
		<xs:annotation>
			<xs:documentation>Flag yes/no</xs:documentation>
		</xs:annotation>
		<xs:restriction base="xs:string">
			<xs:enumeration value="Y"/>
			<xs:enumeration value="N"/>
		</xs:restriction>
	</xs:simpleType>
	<xs:simpleType name="idType">
		<xs:annotation>
			<xs:documentation>Identifier of Simpletask object</xs:documentation>
		</xs:annotation>
		<xs:restriction base="xs:string">
			<xs:maxLength value="100"/>
		</xs:restriction>
	</xs:simpleType>
	<xs:simpleType name="noteType">
		<xs:annotation>
			<xs:documentation>Note in Simpletask</xs:documentation>
		</xs:annotation>
		<xs:restriction base="xs:string">
			<xs:maxLength value="500"/>
		</xs:restriction>
	</xs:simpleType>
	<xs:simpleType name="codeType">
		<xs:annotation>
			<xs:documentation>Code text in simpletask</xs:documentation>
		</xs:annotation>
		<xs:restriction base="xs:string">
			<xs:maxLength value="2000"/>
		</xs:restriction>
	</xs:simpleType>
</xs:schema>
~';
  BEGIN
    BEGIN 
      dbms_xmlschema.deleteSchema(c_schema_id);
    EXCEPTION WHEN others THEN NULL;  END;
    dbms_xmlschema.registerSchema(schemaurl => c_schema_id
     , schemadoc => v_schema
     , local => true, gentypes => false, gentables => false);
  END registerSchema;
------------------------------------------------------------------------------ 
BEGIN
  registerSchema;
END BWTA_XML;
/
show errors;
