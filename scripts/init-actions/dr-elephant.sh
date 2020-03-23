#!/usr/bin/env bash

# Init action for Dr.Elephant

set -euxo pipefail

STAGING_BUCKET='us-staging-pso-wmt-dp-spawner'
MASTER_HOSTNAME=$(/usr/share/google/get_metadata_value attributes/dataproc-master)
readonly MASTER_HOSTNAME

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
  return 1
}

function download() {
  gcloud source repos clone ci-dataproc-dr-elephant /tmp/dr-elephant --project=pso-wmt-data && cd /tmp/dr-elephant
  local APP_REV=$(git describe --tags)
  cd .. && rm -rf /tmp/dr-elephant
  gsutil cp gs://$STAGING_BUCKET/artifacts/dr-elephant-${APP_REV}.zip .
  unzip -q dr-elephant-*.zip -d dist-unpacked/
  mv dist-unpacked/dr-elephant-* /opt/dr-elephant
}

function configure() {
  sed -i 's/^db_password=""/db_password="root-password"/' /opt/dr-elephant/app-conf/elephant.conf

  # Setup Fetchers
  cat <<EOF >/opt/dr-elephant/app-conf/FetcherConf.xml
<?xml version="1.0" encoding="UTF-8"?>

<!--
Copyright 2016 LinkedIn Corp.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.
-->

<fetchers>
  <!--
  <fetcher>
    <applicationtype>tez</applicationtype>
    <classname>com.linkedin.drelephant.tez.fetchers.TezFetcher</classname>
  </fetcher>
  -->
  <fetcher>
    <applicationtype>mapreduce</applicationtype>
    <classname>com.linkedin.drelephant.mapreduce.fetchers.MapReduceFetcherHadoop2</classname>
    <params>
      <sampling_enabled>false</sampling_enabled>
    </params>
  </fetcher>
  <fetcher>
    <applicationtype>mapreduce</applicationtype>
    <classname>com.linkedin.drelephant.mapreduce.fetchers.MapReduceFSFetcherHadoop2</classname>
    <params>
      <sampling_enabled>false</sampling_enabled>
      <history_log_size_limit_in_mb>500</history_log_size_limit_in_mb>
      <history_server_time_zone>UTC</history_server_time_zone>
    </params>
  </fetcher>
  <fetcher>
    <applicationtype>spark</applicationtype>
    <classname>com.linkedin.drelephant.spark.fetchers.FSFetcher</classname>
  </fetcher>
  <fetcher>
    <applicationtype>spark</applicationtype>
    <classname>com.linkedin.drelephant.spark.fetchers.SparkFetcher</classname>
    <params>
      <use_rest_for_eventlogs>true</use_rest_for_eventlogs>
      <should_process_logs_locally>true</should_process_logs_locally>
    </params>
  </fetcher>
  <!--
  <fetcher>
    <applicationtype>tony</applicationtype>
    <classname>com.linkedin.drelephant.tony.fetchers.TonyFetcher</classname>
  </fetcher>
  -->
</fetchers>
EOF

  bdconfig set_property \
    --configuration_file "/opt/dr-elephant/app-conf/GeneralConf.xml" \
    --name 'drelephant.analysis.backfill.enabled' --value 'true' \
    --clobber

  # Enable compression to make metrics accessible by Dr. Elephant
  echo "spark.eventLog.compress = true" >>"/usr/lib/spark/conf/spark-defaults.conf"
}

function prepare_mysql() {
  systemctl restart mysql
  mysql -u root -proot-password -e "CREATE DATABASE drelephant;"
}

function run_dr() {
  # Restart History Server
  systemctl restart spark-history-server
  bash /opt/dr-elephant/bin/start.sh
}

# Install on master node
if [[ "${HOSTNAME}" == "${MASTER_HOSTNAME}" ]]; then
  download || err 'Build step failed'
  configure || err 'Configuration failed'
  prepare_mysql || err 'Could not proceed with mysql'
  run_dr || err 'Cannot launch dr-elephant'
fi
