# CRS804 Sparks 1-4 switch-classified NCCL candidate.
#
# Apply only after capturing RouterOS export/backup and verifying the active
# ports are fabric-port-a, fabric-port-b, fabric-port-c, fabric-port-d.
# Requires existing DSCP 26 -> roce/traffic-class 3 and DSCP 48 -> cnp/
# traffic-class 6 profiles/maps.

/interface ethernet switch qos port set [find where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"] trust-l3=keep pfc=disabled egress-rate-queue3=0
/interface ethernet switch qos tx-manager queue set [find where tx-manager=default and traffic-class=3] schedule=strict-priority ecn=no
