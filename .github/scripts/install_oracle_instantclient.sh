sudo apt-get install wget libaio1t64
sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip -P /tmp
sudo unzip /tmp/instantclient-basiclite-linuxx64.zip -d /opt/oracle
