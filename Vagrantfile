# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Use a base box
  config.vm.box = "bento/ubuntu-24.04"
  
  # Configure the VMs
  config.vm.define "root-ns" do |vm|
    vm.vm.hostname = "root-ns"
    vm.vm.network "private_network", ip: "192.168.121.100"
    vm.vm.provider "libvirt" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    config.vm.provision "shell", path: "setup.sh"
    config.vm.provision "file", source: "NS-Root/CoreFile", destination: "/tmp"
    config.vm.provision "file", source: "NS-Root/db.root", destination: "/tmp"
  end
  
  config.vm.define "test-ns" do |vm|
    vm.vm.hostname = "test-ns"
    vm.vm.network "private_network", ip: "192.168.121.101"
    vm.vm.provider "libvirt" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    config.vm.provision "shell", path: "setup.sh"
    config.vm.provision "file", source: "NS-test/CoreFile", destination: "/tmp"
    config.vm.provision "file", source: "NS-test/db.test", destination: "/tmp"
  end

  config.vm.define "example-test-ns" do |vm|
    vm.vm.hostname = "example-test-ns"
    vm.vm.network "private_network", ip: "192.168.121.102"
    vm.vm.provider "libvirt" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    config.vm.provision "shell", path: "setup.sh"
    config.vm.provision "file", source: "NS-example.test/CoreFile", destination: "/tmp"
    config.vm.provision "file", source: "NS-example.test/db.example.test", destination: "/tmp"
  end

  config.vm.define "resolver" do |vm|
    vm.vm.hostname = "resolver"
    vm.vm.network "private_network", ip: "192.168.121.103"
    vm.vm.provider "libvirt" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
    config.vm.provision "shell", path: "setup.sh"
  end
end
