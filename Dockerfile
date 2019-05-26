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

# install maven
RUN curl -s http://mirror.olnevhost.net/pub/apache/maven/binaries/apache-maven-3.2.1-bin.tar.gz | tar -xz -C /usr/local/
RUN cd /usr/local && ln -s apache-maven-3.2.1 maven
ENV MAVEN_HOME /usr/local/maven
ENV PATH $MAVEN_HOME/bin:$PATH

# download tez code, switch to 0.8.4 branch, compile and copy jars
ENV TEZ_VERSION 0.8.4
ENV TEZ_DIST /usr/local/tez/tez-dist/target/tez-${TEZ_VERSION}
RUN cd /usr/local && git clone https://github.com/apache/tez.git
RUN cd /usr/local/tez && git checkout tags/rel/release-0.8.4 -b branch-0.8 && mvn clean package -DskipTests=true -Dmaven.javadoc.skip=true
RUN $BOOTSTRAP && $HADOOP_PREFIX/bin/hadoop dfsadmin -safemode leave && $HADOOP_PREFIX/bin/hdfs dfs -put ${TEZ_DIST} /tez

# prepare tez ui
RUN mkdir /var/www/tez-ui && cd /var/www/tez-ui && jar -xvf ${TEZ_DIST}/tez-ui2-${TEZ_VERSION}.war
RUN service apache2 restart

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
