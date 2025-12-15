FROM python:3.12-slim

# Install necessary tools and Java (required for Neo4j)
RUN apt-get update && apt-get install vim procps -y \
    ca-certificates wget curl gnupg \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Download and install Neo4j Community Edition
ENV NEO4J_VERSION=5.18.0
RUN mkdir -p /home/big/data/neo4j
RUN mkdir -p /root/.config/gcloud
ENV NEO4J_HOME=/var/lib/neo4j

COPY neo4j-community-${NEO4J_VERSION}-unix.tar.gz /var/lib
WORKDIR /var/lib
RUN tar -xzf neo4j-community-${NEO4J_VERSION}-unix.tar.gz 
RUN mv neo4j-community-${NEO4J_VERSION} ${NEO4J_HOME}
RUN cp ${NEO4J_HOME}/labs/apoc-${NEO4J_VERSION}-core.jar ${NEO4J_HOME}/plugins/

# RUN wget https://dist.neo4j.org/neo4j-community-${NEO4J_VERSION}-unix.tar.gz \
#     && tar -xzf neo4j-community-${NEO4J_VERSION}-unix.tar.gz \
#     && mv neo4j-community-${NEO4J_VERSION} ${NEO4J_HOME} \
#     && rm neo4j-community-${NEO4J_VERSION}-unix.tar.gz \
#     && mkdir -p /var/run/neo4j
# RUN cp ${NEO4J_HOME}/labs/apoc-${NEO4J_VERSION}-core.jar ${NEO4J_HOME}/plugins/

# Set Neo4j environment variables
ENV PATH="${NEO4J_HOME}/bin:${PATH}"

# Configure Neo4j to accept connections from outside the container
RUN sed -i 's/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/' ${NEO4J_HOME}/conf/neo4j.conf

# Install python dependencies
WORKDIR /home
COPY requirements.txt .
RUN pip install --verbose -r requirements.txt
RUN pip install "neo4j-graphrag[google]"

# Expose Neo4j ports
EXPOSE 7474 7687

COPY google-cloud-cli-linux-x86_64.tar.gz /tmp
WORKDIR /tmp
RUN tar -xzf google-cloud-cli-linux-x86_64.tar.gz 
# run on container
# /home/gag/google-cloud-sdk/install.sh            # interactive shell
# /home/gag/google-cloud-sdk/bin/gcloud init
# source /root/.bashrc
# gcloud auth application-default login            # interactive web

