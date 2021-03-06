#!/usr/bin/env bash

set -euxo pipefail

readonly TYPESAFE_ACTIVATOR_URL='https://downloads.typesafe.com/typesafe-activator/1.3.12/typesafe-activator-1.3.12.zip'

# Install base packages
apt install -y wget zip unzip openjdk-8-jdk

# Download and install Typesafe Activator
wget -nv --timeout=30 --tries=5 --retry-connrefused \
  ${TYPESAFE_ACTIVATOR_URL} -O /tmp/typesafe-activator.zip
unzip -q /tmp/typesafe-activator.zip -d /tmp/
mv /tmp/activator-dist-* /tmp/typesafe-activator
export PATH=${PATH}:/tmp/typesafe-activator/bin/

# Install dependencies for new Dr. Elephant UI
curl -sL https://deb.nodesource.com/setup_8.x | bash -
apt install -y nodejs npm
npm install -g bower
pushd web
bower --allow-root install
popd

# Disable tests
sed -i 's/ $OPTS clean compile test $extra_commands/ $OPTS clean compile $extra_commands/' compile.sh

# Set Hadoop and Spark versions
# TODO: fix build with overriden Hadoop and Spark versions
#  local hadoop_version
#  hadoop_version=$(hadoop version 2>&1 | sed -n 's/.*Hadoop[[:blank:]]\+\([0-9]\+\.[0-9]\.[0-9]\+\+\).*/\1/p' | head -n1)
#  local spark_version
#  spark_version=$(spark-submit --version 2>&1 | sed -n 's/.*version[[:blank:]]\+\([0-9]\+\.[0-9]\.[0-9]\+\+\).*/\1/p' | head -n1)
#  sed -i "s/hadoop_version=[0-9.]\+/hadoop_version=${hadoop_version}/" compile.conf
#  sed -i "s/spark_version=[0-9.]\+/spark_version=${spark_version}/" compile.conf

# Set Dr. Elephant version
sed -i "s@APPLICATION_VERSION@${GIT_TAG}@g" build.sbt

# Build Dr. Elephant
bash compile.sh compile.conf
