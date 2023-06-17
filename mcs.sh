#!/bin/bash


if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31;1mThis script requires root privileges. Please run with \`sudo\`.\e[0m"
    exit 1
fi

config_file=mcs.yaml
server_path=$(awk '/^main:/ { p=1; next } p && /server_path:/ { print $2; exit }' "$config_file")

# ? updates the server.properties file in the server directory
function update_properties {
  properties_array=()

  # Extract properties section from the YAML file
  properties_section=$(awk '/^properties:$/,/^$/' "$config_file")

  # Read the key-value pairs from the properties section
  while IFS=':' read -r key value; do
    # Trim leading/trailing whitespace from the key and value
    key=$(echo "$key" | awk '{$1=$1};1')
    value=$(echo "$value" | awk '{$1=$1};1')

    # Skip empty lines and the properties header
    if [[ -n $key ]] && [[ $key != "properties" ]]; then
      # Replace underscore (_) with hyphen (-) in the key
      key=${key//_/-}

      # Append key-value pair to the properties array
      properties_array+=("$key=$value")

      # Alternatively, if you want to include quotes around the value:
      # properties_array+=("$key=\"$value\"")
    fi
  done <<< "$properties_section"  

  for property in "${properties_array[@]}"; do
    key="${property%%=*}"
    value="${property#*=}"

    # Escape special characters in the value
    value="${value//\\/\\\\}"
    value="${value//\//\\\/}"
    value="${value//&/\\&}"
    value="${value//\'/\\\'}"
    value="${value//\"/\\\"}"
    value="${value//\`/\\\`}"
    value="${value//\*/\\\*}"
    value="${value//\?/\\\?}"
    value="${value//\[/\\\[}"
    value="${value//\]/\\\]}"
    value="${value//\$/\\\$}"

    # Replace the property value in the file
    sed -i "s/^\($key=\).*/\1$value/" "$server_path/server.properties"
  done

  echo -e "\e[32mupdated the \e[32;1mserver.properties\e[0m\e[32m file successfully\e[0m"
}
# ? updates the server files
function update_main {
  read -rp "update java? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    echo "updating computer..."
    sudo apt-get update > /dev/null
    java_version=$(grep 'java_version:' "$config_file" | awk '{print $2}')
    echo "updating java..."
    sudo apt-get install openjdk-$java_version-jre-headless > /dev/null
    echo -e "\e[32mupdated java successfully\e[0m"
  fi

  read -rp "update server path? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    read -rp "what was the previous path? " response
    response=${response:-"n"}
    if [ $response = "n" ]; then
      exit 1;
    fi
    mv $server_path $response
    echo -e "\e[32mmoved the server to $response\e[0m"
  fi

  read -rp "update server jar file? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    jar_url=$(grep 'jar_url:' "$config_file" | awk '{print $2}')
    home_dir=$(pwd)
    cd $server_path
    rm server.jar
    wget "$jar_url" --output-document=server.jar > /dev/null
    cd $home_dir
    echo -e "\e[32mupdated the server.jar file\e[0m"
  fi

  read -rp "update the server icon? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    icon_url=$(grep 'icon_url:' "$config_file" | awk '{print $2}')
    home_dir=$(pwd)
    cd $server_path
    rm "server-icon.png"
    wget "$icon_url" --output-document=server-icon.png > /dev/null
    convert server-icon.png -resize 64x64\! server-icon.png
    cd $home_dir
    echo -e "\e[32mupdated the server icon\e[0m"
  fi
}

function start_server {
  max_memory=$(awk '/^main:/ { p=1; next } p && /max_memory:/ { print $2; exit }' "$config_file")
  min_memory=$(awk '/^main:/ { p=1; next } p && /min_memory:/ { print $2; exit }' "$config_file")
  home_dir=$(pwd)
  cd $server_path
  java -Xmx"$max_memory" -Xms"$min_memory" -jar server.jar nogui
}

function remove_server {
  read -rp "do you want to remove the server? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    rm -rf $server_path
    echo -e "\e[31mremoved the server\e[0m"
  else
    echo -e "\e[32mdidn't remove the server\e[0m"
  fi
}

function configure_server {
  echo "updating computer..."
  sudo apt-get update > /dev/null
  java_version=$(grep 'java_version:' "$config_file" | awk '{print $2}')
  echo "updating java..."
  sudo apt-get install openjdk-$java_version-jre-headless > /dev/null
  echo -e "\e[32mupdated java successfully\e[0m"

  mkdir -p $server_path

  touch "$server_path/eula.txt"
  echo "eula=true" > "$server_path/eula.txt"
  echo -e "\e[32maccepted the eula agreements\e[0m"

  jar_url=$(grep 'jar_url:' "$config_file" | awk '{print $2}')
  home_dir=$(pwd)
  cd $server_path
  wget "$jar_url" --output-document=server.jar > /dev/null
  cd $home_dir
  echo -e "\e[32mupdated the server.jar file\e[0m"

  icon_url=$(grep 'icon_url:' "$config_file" | awk '{print $2}')
  home_dir=$(pwd)
  cd $server_path
  wget "$icon_url" --output-document=server-icon.png > /dev/null
  convert server-icon.png -resize 64x64\! server-icon.png
  cd $home_dir
  echo -e "\e[32mupdated the server icon\e[0m"

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

  cd $home_dir
  update_properties
  cd $server_path

  read -rp "start the server? (y/n) [default: n] " response
  response=${response:-"n"}

  if [[ $response =~ ^[Yy]$ ]]; then
    clear
    java -Xmx2048M -Xms1024M -jar server.jar nogui
  fi
}

function add_plugins {
  echo "adding plugins..."
  if [ ! -d "$server_path/plugins" ]; then
    mkdir -p "$server_path/plugins"
  fi
  touch plugins.conf
  for value in "$@"; do
    if grep -q "$value" "plugins.conf"; then
      continue
    fi
    echo "$value" >> plugins.conf
  done

  find "$server_path/plugins" -type f -name "*.jar" -exec rm {} +
  index=0
  home_dir=$(pwd)
  while IFS= read -r value; do
    cd "$server_path/plugins"
    wget "$value" --output-document=plugin"$index".jar
    cd "$home_dir"
    ((index++))
  done < "plugins.conf"
  echo -e "\e[32;1mdownloaded all provided plugins\e[0m"
}


# ? script options

while getopts ":gupsr" opt; do
  case $opt in
    g)
      configure_server
      ;;
    u)
      option="$2"
      if [ ! -z "$option" ]; then
        if [ "$option" = "main" ]; then
          update_main
        elif [ "$option" = "properties" ]; then
          update_properties
        else
          echo -e "\e[31mUnknown option \e[31;1m$option\e[0m"
        fi
      else
        echo -e "\e[31mNo option provided\e[0m"
      fi
      ;;
    p)
      shift
      add_plugins $@
      ;;
    s)
      start_server
      ;;
    r)
      remove_server
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      ;;
  esac
done