# chefNode
User Data

#!/bin/bash
sudo su
cd /opt/
curl -O https://bootstrap.pypa.io/get-pip.py
python get-pip.py --user
export PATH=~/.local/bin:$PATH
source ~/.bash_profile
pip install awscli
echo "access_key
secret_access_key
us-west-2b
"|aws configure
cd /home/ec2-user
aws s3 cp s3://PATH/ /home/ec2-user/ --recursive
sudo su
cd /opt/
yum install git -y
git clone https://github.com/snmsoodan/chefNode.git
cp -r chefNode/chef/ ./
rm -rf chefNode/
cd /home/ec2-user/
ipadd=$(curl ipinfo.io/ip)
ipadd="ec2-user@$ipadd"
echo y|/opt/chef/bin/knife bootstrap $ipadd -i  lmsSecurityKey.pem --ssh-user ec2-user --sudo -r 'recipe[LMS]' --node-name "LMS1"




The chef folder[contains Knife file] for node is in the github. The pem file for the security group and the pem file for the 
server is located in s3 folder.




recipe.dafault
include_recipe 'java_se'

yum_package 'git'

execute 'yum install wget' do
    command 'yum install wget -y'
    action :run
end

execute 'install maven' do
    command 'wget http://www-eu.apache.org/dist/maven/maven-3/3.5.3/binaries/apache-maven-3.5.3-bin.tar.gz'
    cwd '/opt/'
    action :run
end

execute 'untar maven' do
    command 'tar xzvf apache-maven-3.5.3-bin.tar.gz'
    cwd '/opt/'
    action :run
end


#git orchestrator
execute 'git clone orchestrator' do
    command 'git clone https://github.com/snmsoodan/LMSSpringBootOrchestration'
    cwd '/home/ec2-user/'
    action :run
end


execute 'package clean orchestrator' do
    command '/opt/apache-maven-3.5.3/bin/mvn package -f pom.xml'
    cwd '/home/ec2-user/LMSSpringBootOrchestration/LMSSpringBootOrchestration/'
    action :run
end

#git Admin
execute 'git clone Admin' do
    command 'git clone https://github.com/snmsoodan/LMSSpringBootAdmin'
    cwd '/home/ec2-user/'
    action :run
end


execute 'package clean Admin' do
    command '/opt/apache-maven-3.5.3/bin/mvn package -f pom.xml'
    cwd '/home/ec2-user/LMSSpringBootAdmin/LMSSpringBootAdmin/'
    action :run
end





#git Borrower
execute 'git clone Borrower' do
    command 'git clone https://github.com/snmsoodan/LMSSpringBootBorrower'
    cwd '/home/ec2-user/'
    action :run
end


execute 'package clean Borrower' do
    command '/opt/apache-maven-3.5.3/bin/mvn package -f pom.xml'
    cwd '/home/ec2-user/LMSSpringBootBorrower/LMSSpringBootBorrower/'
    action :run
end



#git Librarian
execute 'git clone Librarian' do
    command 'git clone https://github.com/snmsoodan/LMSSpringBootLibrarian'
    cwd '/home/ec2-user/'
    action :run
end


execute 'package clean Librarian' do
    command '/opt/apache-maven-3.5.3/bin/mvn package -f pom.xml'
    cwd '/home/ec2-user/LMSSpringBootLibrarian/LMSSpringBootLibrarian/'
    action :run
end

#run java 
execute 'run orchestrator' do
    command ' nohup java -jar *.jar &'
    cwd '/home/ec2-user/LMSSpringBootOrchestration/LMSSpringBootOrchestration/target/'
    action :run
end


execute 'run Borrower' do
    command 'nohup java -jar *.jar &'
    cwd '/home/ec2-user/LMSSpringBootBorrower/LMSSpringBootBorrower/target/'
    action :run
end


execute 'run Librarian' do
    command 'nohup java -jar *.jar &'
    cwd '/home/ec2-user/LMSSpringBootLibrarian/LMSSpringBootLibrarian/target/'
    action :run
end

execute 'run Admin' do
    command 'nohup java -jar *.jar &'
    cwd '/home/ec2-user/LMSSpringBootAdmin/LMSSpringBootAdmin/target/'
    action :run
end






metadata.rb
depends 'java_se', '~> 10.0'
