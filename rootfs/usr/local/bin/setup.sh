#!/bin/sh
# Nextcloud
##########################

#source setup/functions.sh # load our functions
#source /etc/mailinabox.conf # load global vars
CONFIGFILE=/config/config.php


# Create an initial configuration file.
instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
cat > $CONFIGFILE <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '/data',

  "apps_paths" => array (
      0 => array (
              "path"     => "/app/nextcloud/apps",
              "url"      => "/apps",
              "writable" => false,
      ),
      1 => array (
              "path"     => "/apps2",
              "url"      => "/apps2",
              "writable" => true,
      ),
  ),
  'logfile' => '/tmp/nextcloud.log',
  'loglevel' => '2',
  'log_rotate_size' => '104857600',
  'memcache.local' => '\OC\Memcache\APCu',
  'instanceid' => '$instanceid',
EOF

if [ ! -z $REDIS_HOST ]; then
cat >> $CONFIGFILE <<EOF;
  'memcache.local' => '\OC\Memcache\APCu',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'memcache.locking' => '\OC\Memcache\Redis',
    'redis' =>
    array (
      'host' => '$REDIS_HOST',
      'port' => $REDIS_PORT,
    ),
);
?>
EOF
else
cat >> $CONFIGFILE <<EOF;
);
?>
EOF
fi

# Create an auto-configuration file to fill in database settings
# when the install script is run. Make an administrator account
# here or else the install can't finish.
adminpassword=$(dd if=/dev/urandom bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
cat > /app/nextcloud/config/autoconfig.php <<EOF;
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory'     => '/data',
  'dbtype'        => '${DB_TYPE:-sqlite3}',
  'dbname'        => '${DB_NAME:-nextcloud}',
  'dbuser'        => '${DB_USER:-nextcloud}',
  'dbpass'        => '${DB_PASSWORD:-password}',
  'dbhost'        => '${DB_HOST:-nextcloud-db}',
  'dbtableprefix' => 'oc_',
EOF
if [[ ! -z "$ADMIN_USER"  ]]; then
  cat >> /app/nextcloud/config/autoconfig.php <<EOF;
  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of ownCloud
  'adminlogin'    => '${ADMIN_USER}',
  'adminpass'     => '${ADMIN_PASSWORD}',
EOF
fi
cat >> /app/nextcloud/config/autoconfig.php <<EOF;
);
?>
EOF

if [[ "$DB_TYPE" == "mysql" ]]; then
  for i in $(seq 10); do
    echo "[$i/10] Test db connection ..."
    php -r "mysqli_connect('$DB_HOST', '$DB_USER', '$DB_PASSWORD') or exit(1);" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      echo "Test db connection done"
      break
    fi
    if [[ $i -eq 10 ]]; then
      echo "Test db connection failed"
      exit 1
    fi
    sleep 5
  done
elif [[ "$DB_TYPE" == "pgsql" ]]; then
  for i in $(seq 20); do
    echo "[$i/10] Test db connection ..."
    php -r "pg_connect ('host=$DB_HOST user=$DB_USER password=$DB_PASSWORD') or exit(1);" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      echo "Test db connection done"
      break
    fi
    if [[ $i -eq 20 ]]; then
      echo "Test db connection failed"
      exit 1
    fi
    sleep 5
  done
fi

echo "Starting automatic configuration..."
# Execute ownCloud's setup step, which creates the ownCloud database.
# It also wipes it if it exists. And it updates config.php with database
# settings and deletes the autoconfig.php file.
(cd /app/nextcloud; php index.php &>/dev/null)
echo "Automatic configuration finished."

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# Use PHP to read the settings file, modify it, and write out the new settings array.

CONFIG_TEMP=$(/bin/mktemp)
php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP $CONFIGFILE
<?php
include("/config/config.php");

//\$CONFIG['memcache.local'] = '\\OC\\Memcache\\Memcached';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches our master administrator address

\$CONFIG['logtimezone'] = '$TZ';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF

sed -i "s/localhost/$DOMAIN/g" /config/config.php

chown -R $UID:$GID /config /data
# Enable/disable apps. Note that this must be done after the ownCloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows ownCloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
if [[ ! -z "$ADMIN_USER"  ]]; then
  occ app:disable firstrunwizard
fi
