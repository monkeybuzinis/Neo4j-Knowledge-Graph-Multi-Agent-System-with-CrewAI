import os, asyncio
from dotenv import load_dotenv
from neo4j import GraphDatabase
from neo4j_graphrag.llm import VertexAILLM
from neo4j_graphrag.embeddings import VertexAIEmbeddings
from neo4j_graphrag.experimental.pipeline.kg_builder import SimpleKGPipeline
from neo4j_graphrag.experimental.components.text_splitters.fixed_size_splitter import FixedSizeSplitter
load_dotenv()

neo4j_driver = GraphDatabase.driver( os.getenv("NEO4J_URI")
,   auth=(os.getenv("NEO4J_USERNAME"), os.getenv("NEO4J_PASSWORD")) )
neo4j_driver.verify_connectivity()

#a with chunk size 500, 2 county level node gets created.  
#  chunk 5000 fixes this, but it's a cheat.
llm = VertexAILLM( model_name="gemini-2.5-flash"
,   model_params={ "temperature": 0
,   "response_format": {"type": "json_object"},  } )
embedder = VertexAIEmbeddings( model="text-embedding-005" )
text_splitter = FixedSizeSplitter(chunk_size=3000, chunk_overlap=500) #a

node_types = [ "domain", "timeframe", "org", "disorder", "hierarchy", "money"
, {  "label":"cXs", "properties"
: [ { "name":"name"     , "type":"STRING", "required":True}
,   { "name":"desc"     , "type":"STRING", "required":True}
,   { "name":"frequency", "type":"STRING", "required":False}
,   { "name":"format"   , "type":"STRING", "required":True}
,   { "name":"example"  , "type":"STRING", "required":True}
,   { "name":"longname" , "type":"STRING", "required":False} ] } ]
rela_types = [ "contains", "covers", "sends_money", "sends_data", "creates" ]
patterns   = [ ("domain", "contains", "domain"), ("domain", "covers", "disorder")
, ("org", "sends_money", "org") , ("hierarchy", "contains", "org")
, ("org", "sends_data" , "org") , ("hierarchy", "covers"  , "hierarchy")
, ("org", "creates"    , "cXs"),  ]

kg_builder = SimpleKGPipeline( llm=llm, driver=neo4j_driver
,   neo4j_database=os.getenv("NEO4J_DATABASE"),  embedder=embedder
,   from_pdf=True, text_splitter=text_splitter
,   schema={ "node_types": node_types, "relationship_types": rela_types
,   "patterns": patterns }, )

pdf_file = "/home/gag/genai-graphrag-python/data/schema.pdf"
result = asyncio.run(kg_builder.run_async(file_path=pdf_file))
print(result.result)
