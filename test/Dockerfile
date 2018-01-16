# Base image to build from
FROM juanbrein/base

# Mantainer:
MAINTAINER Breinlinger Juan Paulo <juan.brein@breins.net>

# Some Environment Variables
ENV DEBIAN_FRONTEND noninteractive
ENV HOME /root

# Add all the files
ADD root.tar.gz /

# Run it:
CMD ["/start.sh"]
