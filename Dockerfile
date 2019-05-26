FROM bde2020/hadoop-base:2.0.0-hadoop2.7.4-java8

# Allow buildtime config of HIVE_VERSION
ARG HIVE_VERSION
# Set HIVE_VERSION from arg if provided at build, env if provided at run, or default
# https://docs.docker.com/engine/reference/builder/#using-arg-variables
# https://docs.docker.com/engine/reference/builder/#environment-replacement
ENV HIVE_VERSION=${HIVE_VERSION:-2.3.2}

ENV HIVE_HOME /opt/hive
ENV PATH $HIVE_HOME/bin:$PATH
ENV HADOOP_HOME /opt/hadoop-$HADOOP_VERSION

WORKDIR /opt
RUN cat /etc/apt/sources.list
RUN echo "deb [check-valid-until=no] http://archive.debian.org/debian jessie main" > /etc/apt/sources.list.d/jessie.list


RUN sed -i '/deb http:\/\/deb.debian.org\/debian jessie-updates main/d' /etc/apt/sources.list
RUN sed -i '/deb http:\/\/ftp.debian.org\/debian jessie-backports main/d' /etc/apt/sources.list

RUN apt-get -o Acquire::Check-Valid-Until=false update

#Install Hive and PostgreSQL JDBC
RUN apt-get install -y wget procps && \
	wget https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz && \
	tar -xzvf apache-hive-$HIVE_VERSION-bin.tar.gz && \
	mv apache-hive-$HIVE_VERSION-bin hive && \
	wget https://jdbc.postgresql.org/download/postgresql-9.4.1212.jar -O $HIVE_HOME/lib/postgresql-jdbc.jar && \
	rm apache-hive-$HIVE_VERSION-bin.tar.gz && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# MSSQL jdbc driver
RUN wget https://download.microsoft.com/download/B/F/9/BF9C2615-C802-400C-AC90-F3F29EF07B3B/sqljdbc_6.2.2.1_rus.tar.gz
RUN tar xzf sqljdbc_6.2.2.1_rus.tar.gz
RUN mv sqljdbc_6.2/rus/mssql-jdbc-6.2.2.jre8.jar $HIVE_HOME/lib/

#Spark should be compiled with Hive to be able to use it
#hive-site.xml should be copied to $SPARK_HOME/conf folder

#Custom configuration goes here
ADD conf/hive-site.xml $HIVE_HOME/conf
ADD conf/beeline-log4j2.properties $HIVE_HOME/conf
ADD conf/hive-env.sh $HIVE_HOME/conf
ADD conf/hive-exec-log4j2.properties $HIVE_HOME/conf
ADD conf/hive-log4j2.properties $HIVE_HOME/conf
ADD conf/ivysettings.xml $HIVE_HOME/conf
ADD conf/llap-daemon-log4j2.properties $HIVE_HOME/conf

COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 10000
EXPOSE 10002

# to run bower as root
RUN echo '{ "allow_root": true }' > /root/.bowerrc

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24
RUN echo 'deb http://ppa.launchpad.net/git-core/ppa/ubuntu trusty main' > /etc/apt/sources.list.d/git.list
RUN apt-get update
RUN apt-get install -y git

ENV TEZ_DIST /usr/local/tez

RUN mkdir -p $TEZ_DIST
# download tez code, switch to 0.8.4 branch, compile and copy jars
RUN wget http://apache-mirror.rbc.ru/pub/apache/tez/0.9.2/apache-tez-0.9.2-bin.tar.gz
RUN tar xzf apache-tez-0.9.2-bin.tar.gz
RUN mv apache-tez-0.9.2-bin $TEZ_DIST
RUN $HADOOP_PREFIX/bin/hdfs dfs -mkdir /tez
RUN $BOOTSTRAP && $HADOOP_PREFIX/bin/hdfs dfs -put $TEZ_DIST /tez

# add site files
ADD conf/tez-site.xml $HADOOP_PREFIX/etc/hadoop/tez-site.xml
ADD conf/mapred-site.xml $HADOOP_PREFIX/etc/hadoop/mapred-site.xml

# environment settings
RUN echo 'TEZ_JARS=${TEZ_DIST}/*' >> $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
RUN echo 'TEZ_LIB=${TEZ_DIST}/lib/*' >> $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
RUN echo 'TEZ_CONF=/usr/local/hadoop/etc/hadoop' >> $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
RUN echo 'export HADOOP_CLASSPATH=$HADOOP_CLASSPATH:$TEZ_CONF:$TEZ_JARS:$TEZ_LIB' >> $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh


ENTRYPOINT ["entrypoint.sh"]
CMD startup.sh
