#!/bin/bash
# test shell for creating numbered vrf interfaces
# Usage - apply router numbers to all hosts that you want to affect changes into 
# these numbers are the baseline for all changes
# updated 8/26 /2007 by Colin McNamara
# http://www.colinmcnamara.com
# colin@2cups.com
# test variable - add a for loop calling out variable in production from list
# note- in this script vrf's have to numbers.
# note- make the vrf's network numbers....

# note avoid VRF 1 (it screws with outbound vlans)
# start at 5 


vrfnumbers="5 7 9 11 13 15 17 19 21 23 25 27 29 31 33 35 37 39 41 43 45 47 49 51 53 55 57 59 61"
#vrfnumbers="5 7 9"

# define your edge chassis numbers, note that most of the time, cores take up #'s 1 and 2
edgenumbers="3 4 5 6 7 8 9 10"

# what /16 should be used for uplinks
uplinknet="10.253"

# what will your fusion VRF be?
fusionvrf="254"

# what is your ospf password (should add a random pass gen code here
ospfpass=""

# what are you using for hsrp authentication
hsrpauth=""

# what is your hello multiplier (how many times a second is ospf going to chat accross your link)
hellomultiplier="5"

# what is the default administrative status of your master portchannel interfaces
adminstatus="no shut"

# what is the default administrative status of your child (vrf) portchannel subinterface interfaces
subadminstatus="no shut"

# define the domain name for ssh and dns
domainname="vrfdomain"

# core chassis numbers
core1="1"
core2="2"

# core hsrp ip address last octects

coreiphsrp=$((core1+1))
coreip2hsrp=$((core1+2))
corehsrp=$((core1))

# dedicate /16 to uplinks
# 3rd octet is chassis number
# e.g. chassis 1 uplinks will be $uplinknet.1.0/24 for uplinks
# e.g. chassis 2 uplinks will be $uplinknet.2.0/24 for uplinks
# this will allows for 64 vrf's
# you could use smaller subnets (without broadcast or network address's to get 128 subnets
# use /31's for vrf's
# naming variables for dot1q interface
# first character = uplink number (1 or 2)
# 2nd character equals vrf number
#
# port channel numbers
# uplink chassis number + edge chassis number
# e.g. core 1 to edge 1 would be po11
# e.g. core 2 to edge 2 would be po21
# 
#

# create some templates for later use 
# create base config template for core trunks #  

for trunktemplate in $core1 $core2
do
echo "! ##### core vlan trunk (layer2) ####
 int port-channel $core1$core2 
 switchport
 description portchanne$core1$core2 between cores                                         
 switchport                                                                     
 switchport trunk encapsulation dot1q                                           
 switchport trunk native vlan 1000                                              
 switchport mode trunk                                                          
 no ip address 
 $adminstatus
 ! 
 !" > core$trunktemplate.template.trunk.tmp

done

for fusionrd in $core1 $core2
do
# create the route descriptor for the fusion vrf
echo "! ####### fusion vrf route descriptor ####
 ip vrf $fusionvrf
 rd $fusionvrf:$fusionvrf
!
!" > core$fusionrd.routedescriptor.tmp
done

# always start at 3  (cores are 1 and 2) 
# maximum layer 3 devices = 251
for edge in $edgenumbers 
do

# edge1
#
# lets make some port channel configs
#
# create uplink to first core
#

for vrf in $vrfnumbers
do 
# used to address the uplink address's

coreip=$((vrf-1))
edgeip=$((vrf+0))


# uplink address last octets

coreip2=$((vrf+127))
edgeip2=$((vrf+128))


# create the vrf route descriptors
echo "ip vrf $vrf
 rd $vrf:$vrf
 !" > all.1.rd.vrf.$vrf.vrf.cfg.tmp

# create static routes to the firewall (trust side)
for staticroute in $core1 $core2
do
echo "! static route to firewall service module context (or interface) for the trust side
ip route vrf $vrf 0.0.0.0 0.0.0.0 10.$vrf.254.241
!
!" > core$staticroute.vrf$vrf.static.cfg.tmp

done
  
# create static routes to the firewall / walls on the fusion routers

for fusionstaticroute in $core1 $core2
do
echo "! static route to firewall service module context (or interface) for the trust side
ip route vrf $fusionvrf  10.$vrf.0.0 255.255.0.0 10.254.254.$vrf 
!
!" > core$fusionstaticroute.fusion.vrf$vrf.static.tmp

done


# lets create some loobacks for the edge devices
echo "! edge $edge vrf $vrf loopback
 interface Loopback$vrf
 ip vrf forwarding $vrf
 ip address 10.252.$edge.$vrf 255.255.255.255
 $subadminstatus
 !" > edge$edge.vrf$vrf.loopback.tmp


# lets create some loobacks for the cores

for coreloop in $core1 $core2
do
# cores
echo "! core $coreloop vrf $vrf loopback
 interface Loopback$vrf
 ip vrf forwarding $vrf
 ip address 10.252.$coreloop.$vrf 255.255.255.255
 $subadminstatus
 !" > core$coreloop.vrf$vrf.loopback.tmp
done

# create some ospf configs
# (bgp section coming soon)

echo "router ospf $vrf vrf $vrf
 log-adjacency-changes
 capability vrf-lite
 area 0 authentication message-digest
 area 1 authentication message-digest
 network $uplinknet.0.0 0.0.255.255 area 0
 network 10.252.0.0 0.0.255.255 area 0
 network 10.$vrf.0.0 0.0.255.255 area 1
 no passive-interface default

 !
 
 !" > all.2.ospf.vrf$vrf.$edge.ospf.tmp 
# !" > ospf.vrf$vrf.1.$edge.ospf.tmp
### copying all.2 into all.3 for core updates
cp all.2.ospf.vrf$vrf.$edge.ospf.tmp all.3.ospf.vrf$vrf.$edge.ospf.tmp
### edge fwsm border vlan configs

for fwsmvlan in $core1 $core2 
do
echo "! vlan configurations for core$core1 vrf$vrf
 vlan $vrf
 name vrf$vrf-fwsm-border-vlan 
 firewall autostate                                                              
 firewall multiple-vlan-interfaces  
 firewall module 1 vlan-group 1  
 firewall vlan-group 1 $vrf
 !
 !" > core$fwsmvlan.vrf$vrf.fwsm.vlan.tmp
done

for trunkloop in $core1 $core2
do
# add vrf to core trunks
echo "!### add vrf to core trunks
 switchport trunk allowed vlan add $vrf
 ! 
 !" > tmp.core$trunkloop.vrf$vrf.template.trunk.tmp
cat tmp.core$trunkloop.vrf$vrf.template.trunk.tmp >> core$trunkloop.template.trunk.tmp
done

 
### TO FIRST CORE config files ###

echo "!###### core1 to edge$edge vrf $vrf configuration file#########
 int port-channel $core1$edge
 $adminstatus
 !vrf number $vrf
 int port-channel $core1$edge.$vrf
 encapsulation dot1Q $core1$edge$vrf 
 ip vrf forwarding $vrf
 ip address $uplinknet.$edge.$coreip 255.255.255.254
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > core$core1.edge$edge.vrf$vrf.portchannel.tmp

echo "!###### edge$edge to core1 vrf $vrf configuration file#########
 int port-channel $core1$edge
 $adminstatus
 !vrf number $vrf
 int port-channel $core1$edge.$vrf
 encapsulation dot1Q $core1$edge$vrf 
 ip vrf forwarding $vrf
 ip address $uplinknet.$edge.$vrf 255.255.255.254
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > edge$edge.core$core1.vrf$vrf.portchannel.tmp

# create edge vlan interface to the fwsm

echo "interface Vlan$vrf                                                                
 ip vrf forwarding $vrf                                                      
 ip address 10.$vrf.254.$coreiphsrp 255.255.255.0                                            
 standby ip 10.$vrf.254.$corehsrp                                                          
 standby 1 authentication $hsrpauth 
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > core$core1.vrf$vrf.edge.vlan.tmp

# export edge vlan to the fwsm

### TO SECOND CORE ######

echo "!###### core2 to edge$edge vrf $vrf configuration file#########
 int port-channel $core2$edge
 $adminstatus
 !vrf number $vrf
 int port-channel $core2$edge.$vrf
 encapsulation dot1Q $core2$edge$vrf 
 ip vrf forwarding $vrf
 ip address $uplinknet.$edge.$coreip2 255.255.255.254
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > core$core2.edge$edge.vrf$vrf.portchannel.tmp



echo "!###### edge$edge to core2 vrf $vrf configuration file#########
 int port-channel $core2$edge
 $adminstatus
 !vrf number $vrf
 int port-channel $core2$edge.$vrf
 encapsulation dot1Q $core2$edge$vrf 
 ip vrf forwarding $vrf
 ip address $uplinknet.$edge.$edgeip2 255.255.255.254
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > edge$edge.core$core2.vrf$vrf.portchannel.tmp


# Create edge vlan interface to the fwsm #

echo "interface Vlan$vrf                                                                
 ip vrf forwarding $vrf                                                      
 ip address 10.$vrf.254.$coreip2hsrp 255.255.255.0                                            
 standby ip 10.$vrf.254.$corehsrp                                                          
 standby 1 authentication $hsrpauth 
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $ospfpass
 ip ospf dead-interval minimal hello-multiplier $hellomultiplier
 $subadminstatus
 !
 !" > core$core2.vrf$vrf.edge.vlan.tmp


######################### begin FWSM stuff #########################

# create fwsm context per vrf
echo "! ########### fwsm context vrf$vrf configuration #########                                                                             
hostname vrf$vrf                                                                   
domain-name $domainname                                                                  
names                                                                           
!                                                                               
interface Vlan$vrf                                                                
 nameif trust-vrf$vrf                                                              
 security-level 100                                                             
 ip address 10.$vrf.254.241 255.255.255.240 standby 10.$vrf.254.243               
!                                                                               
interface Vlan$fusionvrf                                                                
 nameif fusion-$fusionvrf                                                             
 security-level 0                                                               
 ip address 10.$fusionvrf.254.$vrf 255.255.255.0 standby 10.$fusionvrf.254.1$vrf                      
!                                                                               
pager lines 24                                                                  
mtu trust-vrf$vrf 1500                                                             
mtu fusion-254 1500                                                            
ip verify reverse-path interface trust-vrf$vrf                                     
icmp permit any echo trust-vrf$vrf                                                 
icmp permit any echo-reply trust-vrf$vrf                                           
icmp permit any echo trust-vrf$vrf                                                
icmp permit any echo-reply trust-vrf$vrf                                          
route trust-vrf$vrf 10.$vrf.0.0 255.255.0.0 10.$vrf.254.1 1                        
route fusion-$fusionvrf 0.0.0.0 0.0.0.0 10.$fusionvrf.254.1 1                                  
!
!" > fwsm.context.vrf$vrf.tmp  

done

cat all.1*.tmp > edge$edge.cfg
cat edge$edge*.tmp  >> edge$edge.cfg
cat all.2*.tmp >> edge$edge.cfg
### clean up all.2's so we don't have huge configs on our edges
rm -rf all.2*.tmp
cat fwsm*.tmp > fwsm.context.cfg

done
cat all.1*.tmp > core$core1.cfg
cat core$core1*.tmp >> core$core1.cfg
cat all.3*.tmp >> core$core1.cfg
 
cat all.1*.tmp > core$core2.cfg
cat core$core2*.tmp >> core$core2.cfg
cat all.3*.tmp >> core$core2.cfg

rm -rf *.tmp

