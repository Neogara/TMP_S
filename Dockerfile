FROM openjdk:8-jdk-stretch

RUN apt-get update && apt-get upgrade -y && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home
ARG REF=/usr/share/jenkins/ref

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF

RUN mkdir -p $JENKINS_HOME \
  && chown ${uid}:${gid} $JENKINS_HOME \
  && groupadd -g ${gid} ${group} \
  && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}
  
VOLUME $JENKINS_HOME

RUN mkdir -p ${REF}/init.groovy.d

ARG TINI_VERSION=v0.16.1
COPY tini_pub.gpg ${JENKINS_HOME}/tini_pub.gpg
RUN curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture) -o /sbin/tini \
  && curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture).asc -o /sbin/tini.asc \
  && gpg --no-tty --import ${JENKINS_HOME}/tini_pub.gpg \
  && gpg --verify /sbin/tini.asc \
  && rm -rf /sbin/tini.asc /root/.gnupg \
  && chmod +x /sbin/tini


ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.176.2}
ARG JENKINS_SHA=33a6c3161cf8de9c8729fd83914d781319fd1569acf487c7b1121681dba190a5
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" "$REF"


EXPOSE ${http_port}
EXPOSE ${agent_port}
ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log
USER ${user}
COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh

FROM ubuntu:18.04
LABEL maintainer "Pawlin"
ENV HTTP_PORT 8067
ENV WEBSOCKET_PORT 9067
ENV CENTRAL_DATA_IP 192.168.103.243
WORKDIR /var/www/adainterface
RUN apt-get update -y
RUN apt-get install -y curl
RUN apt-get install -y software-properties-common
RUN add-apt-repository ppa:wireshark-dev/stable -y
RUN add-apt-repository ppa:jonathonf/python-3.6 -y
RUN curl -s https://s3.amazonaws.com/download.draios.com/DRAIOS-GPG-KEY.public | apt-key add -  
RUN curl -s -o /etc/apt/sources.list.d/draios.list https://s3.amazonaws.com/download.draios.com/stable/deb/draios.list  
RUN apt-get update -y
RUN apt-get -y install linux-headers-$(uname -r)
RUN apt-get -y install sysdig
RUN curl -sL https://deb.nodesource.com/setup_11.x | bash
RUN apt-get update -y
RUN apt-get install -y nodejs python3.6
RUN apt-get install -y debconf-utils
RUN echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections -v
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y tshark
RUN chmod +x /usr/bin/dumpcap
RUN npm install npm@latest -g
COPY . .
RUN npm install
RUN npm audit fix
RUN cat /dev/null > /var/www/adainterface/app/forever/common.log
RUN	cat /dev/null > /var/www/adainterface/app/forever/error.log
RUN	cat /dev/null > /var/www/adainterface/app/forever/out.log
RUN npm run uconfig -- pset http $HTTP_PORT -a
RUN npm run uconfig -- pset wsok $WEBSOCKET_PORT -a
RUN sed -ie "s|^        \"USERNAME\":.*|        \"USERNAME\":\"root\",|" app/public/javascripts/filler.js 
RUN sed -ie "s|^    \"central_local_ip\":.*|    \"central_local_ip\":\"$CENTRAL_DATA_IP\",|" config/production.json
RUN sed -ie "s|^    \"central_local_ip\":.*|    \"central_local_ip\":\"$CENTRAL_DATA_IP\",|" config/development.json
EXPOSE $HTTP_PORT
EXPOSE $WEBSOCKET_PORT
