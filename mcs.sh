#!/bin/bash


if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31;1mThis script requires root privileges. Please run with sudo.\e[0m"
    exit 1
fi

clear

config_file="mcs-config.yaml"

if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
    echo "Config file '$config_file' is empty or non-existing. Exiting..."
    exit 1
fi

# ?function `parse_yaml` by `https://stackoverflow.com/users/1792684/stefan-farestam`
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml $config_file)

echo -e "\e[32mimported config\e[0m"

#? configurating server
echo "Starting the server configuration..."

apt-get update > /dev/null
echo -e "\e[32mupdated packages\e[0m"

apt-get install openjdk-$java_version-jre > /dev/null
echo -e "\e[32minstalled java version \e[32;1m$java_version\e[0m"

mkdir -p "$server_path"

wget "$jar_url" --output-document=server.jar > /dev/null
mv "server.jar" "$server_path/server.jar"
echo -e "\e[32mdownloaded the server file\e[0m"

if [ ! -f "plugins.conf" ]; then
    touch "plugins.conf"
    echo -e "\e[32mcreated the plugins.conf file\e[0m"
fi

if [ -s "plugins.conf" ]; then
    mapfile -t plugins < plugins.conf
    mkdir "$server_path/plugins"
    
    touch "$server_path/plugins/readme.md"
    echo "The files are indexed in the order that they where put in the **plugins.conf** file." > readme.md
    
    echo "downloading plugins..."
    for index in "${!plugins[@]}"; do
        wget "${plugins[$index]}" > /dev/null
        mv "download" "$server_path/plugins/plugin$index.jar"
    done
    echo -e "\e[32mdownloaded plugins\e[0m"
else
    echo -e "\e[31mthe \e[31;1mplugins.conf\e[0m\e[31m file is empty\e[0m"
fi

touch "$server_path/eula.txt"
echo "eula=true" > "$server_path/eula.txt"
echo -e "\e[32maccepted the eula agreements\e[0m"

echo "installing server files..."
cd $server_path
java -Xmx2048M -Xms1024M -jar server.jar nogui > /dev/null &

#? Save the PID of the Java process
java_pid=$!

#? Wait until the server starts
until lsof -i :25565 | grep LISTEN > /dev/null; do
    sleep 1
done

sleep 30

kill $java_pid

sleep 30
echo -e "\e[32minstallation completed.\e[0m"

sed -i "s/difficulty=easy/difficulty=$properties_difficulty/" "$server_path/server.properties"
sed -i "s/motd=A Minecraft Server/motd=$properties_motd/" "$server_path/server.properties"

wget "$icon_url" --output-document=server-icon.png > /dev/null

convert server-icon.png -resize 64x64\! server-icon.png

read -rp "start the server? (y/n) [default: n] " response
response=${response:-"n"}

if [[ $response =~ ^[Yy]$ ]]; then
   clear
   java -Xmx2048M -Xms1024M -jar server.jar nogui
fi

#https://www.curseforge.com/api/v1/mods/31043/files/4586220/download
