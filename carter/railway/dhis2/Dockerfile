# DHIS2 2.43.2.1 for Railway. Railway has no bind mounts, so config is baked in;
# all secrets/hosts come from service variables via ${VAR} in dhis.conf.
FROM dhis2/core:2.43.2.1
COPY dhis.conf /opt/dhis2/dhis.conf
COPY log4j2.xml /opt/dhis2/log4j2.xml
