
Vagrant.configure("2") do |config|
  PROJECT="anvils"
  RDIP="192.168.50.2"
  RUNDECK_YUM_REPO="https://bintray.com/rundeck/rundeck-rpm/rpm"
  #RUNDECK_YUM_REPO="https://bintray.com/rundeck/ci-staging-rpm/rpm"

  config.ssh.insert_key = false
  config.vm.box = "bento/centos-6.7"

  # uncomment for faster performance
  #config.vm.provider "virtualbox" do |vb|
  #  vb.cpus = "2"
  #  vb.memory = "4096"
  #end

  config.vm.define :rundeck do |rundeck|
    rundeck.vm.hostname = "rundeck.anvils.com"
    rundeck.vm.network :private_network, ip: "#{RDIP}"

    ### uncomment for work around for issue#20 ######
    #rundeck.vm.provision :shell, inline: "yum install epel-release -y"
    ####################

    rundeck.vm.provision :shell, :path => "install-rundeck.sh", :args => "#{RDIP} #{RUNDECK_YUM_REPO}"
    rundeck.vm.provision :shell, :path => "install-httpd.sh"
    rundeck.vm.provision :shell, :path => "add-project.sh", :args => "#{PROJECT}"
  end
end
