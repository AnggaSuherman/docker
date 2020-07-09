FROM centos:7.6.1810

# RUN echo $'[griddb]\n\
# name=GridDB.net\n\
# baseurl=https://griddb.net/yum/el7/4.5/\n\
# enabled=1\n\
# gpgcheck=1\n\
# gpgkey=https://griddb.net/yum/RPM-GPG-KEY-GridDB.txt\n '\
# >> /etc/yum.repos.d/griddb.repo

# RUN yum -y install griddb  
# RUN yum -y install griddb-c-client

RUN rpm -i https://github.com/griddb/griddb/releases/download/v4.5.0/griddb-4.5.0-1.linux.x86_64.rpm

ENV GS_HOME /var/lib/gridstore
ENV GS_LOG $GS_HOME/log
ENV HOME $GS_HOME

WORKDIR $HOME

ADD griddb.sh /
USER gsadm

ENTRYPOINT ["/griddb.sh"]

# CMD /griddb.sh
EXPOSE 10001 10010 10020 10030 10040 10050 10080 20001

