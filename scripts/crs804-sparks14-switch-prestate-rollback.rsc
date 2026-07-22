# CRS804 Sparks 1-4 rollback to the pre-campaign live state captured on
# 2026-07-01 in evidence/crs804-switch-campaign-20260701-152637/task02-switch-prestate.

/interface ethernet switch qos port set [find where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"] trust-l3=keep pfc=pfc-tc3 egress-rate-queue3=100.0Gbps
/interface ethernet switch qos tx-manager queue set [find where tx-manager=default and traffic-class=3] schedule=high-priority-group weight=1 ecn=yes
