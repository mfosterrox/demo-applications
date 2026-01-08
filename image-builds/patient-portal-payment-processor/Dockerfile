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

FROM quay.io/hummingbird/python:3.14 AS build

# Build packages to a writable location (/tmp is typically writable)
RUN pip install --no-cache-dir --target /tmp/packages starlette uvicorn

FROM quay.io/hummingbird/python:3.14 AS run

# Copy packages to user-writable location and set PYTHONPATH
# COPY automatically creates directories
COPY --chown=1001:0 --from=build /tmp/packages /home/fritz/packages
COPY --chown=1001:0 main.py /home/fritz/main.py

EXPOSE 8080
WORKDIR /home/fritz
ENV PYTHONPATH=/home/fritz/packages:$PYTHONPATH
USER 1001
ENTRYPOINT ["python", "main.py"]
