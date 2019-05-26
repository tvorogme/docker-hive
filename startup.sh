#!/bin/bash

hadoop fs -mkdir       /tmp
hadoop fs -mkdir -p    /user/hive/warehouse
hadoop fs -chmod g+w   /tmp
hadoop fs -chmod g+w   /user/hive/warehouse
hadoop fs -mkdir -p /opt/hive/lib
hadoop fs -put $HIVE_HOME/lib/hive-druid-handler-2.3.2.jar $HIVE_HOME/lib/hive-druid-handler-2.3.2.jar


export BROKER_IP=$(route | head -3 | tail -1 | awk '{print $2}')

cd $HIVE_HOME/bin
./hiveserver2 --hiveconf hive.server2.enable.doAs=false --hiveconf hive.druid.broker.address.default $BROKER_IP
