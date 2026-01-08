#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

FROM quay.io/hummingbird/postgresql

ENV POSTGRES_USER=patient_portal
ENV POSTGRES_PASSWORD=secret
ENV POSTGRES_HOST_AUTH_METHOD=scram-sha-256
ENV POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256

COPY data.sql /docker-entrypoint-initdb.d/data.sql
COPY --chmod=755 entrypoint-wrapper.sh /entrypoint-wrapper.sh

# Create pgdata directory as root with proper permissions for OpenShift
USER root
RUN mkdir -p /pgdata/data && \
    chgrp -R root /pgdata && \
    chmod -R g+rwX /pgdata

# Set PGDATA
ENV PGDATA=/pgdata/data

# Use sh to execute the script to avoid permission issues
ENTRYPOINT ["sh", "/entrypoint-wrapper.sh"]
CMD ["postgres"]
