#!/bin/bash
# Install script for 'anwesende'.

# ########## constants:

ANW=anw  # shorter form of 'anwesende'
ENVSDIR=.envs
ENVSSRCDIR=config/envs
TRAEFIK_YML=compose/traefik/traefik.yml
DOCKER_COMPOSE_YML=docker-compose.yml
DOCKERENV_ENV=$ENVSDIR/autogenerated.env
MYENV_ENV=$ENVSDIR/myenv.env
PATCHENV=config/envs/patch_env.py

# image names are hardcoded, see make_docker_compose_yml and transfer_images


# ########## usage:

if [ $# -lt 2 ]; then 
  cat <<ENDOFFILE
anw env cmd args...
  env   reads environment variables from $ENVSDIR/{env}.sh
  cmd   is a command defined in the $0 script (list them with '$0 - help')
  args  are cmd-dependent arguments, most often none.
  Install script, see README.md for a description.
  Will read the files 
    ${MYENV_ENV} and $ENVSDIR/{env}.sh
  and use the settings therein to generate the following files on the fly:
    $DOCKER_COMPOSE_YML  (which configures docker)
    $DOCKERENV_ENV  (used to hand environment into the docker containers)
    $TRAEFIK_YML  (for deploymodes LETSENCRYPT and CERTS only)
  There is no error handling, so be careful what you do.
ENDOFFILE
  exit 1
fi

# ########## individual command functions (externally visible):

help()   # args: 
{
  announce "########## help: anw commands"
  egrep '\(\) *[#] args:' $myself | sed 's/() *[#] args:/ /'  # (must not match itself)
}

prepare_envs()   # args:   (step 1)
{
  announce $FUNCNAME
  mkdir -p $ENVSDIR
  set -o xtrace
  cp -u $ENVSSRCDIR/myenv-template.env $ENVSDIR/myenv.env
  cp -u $ENVSSRCDIR/production-template.sh $ENVSDIR/production.sh
  set +o xtrace
  announce $FUNCNAME end
}

docker_login()   # args:   (step 2)
{
  announce $FUNCNAME
  docker login -u ${REGISTRYUSER} ${REGISTRY}
  if [ ! $REMOTE ]; then
    ssh -t $TUTH docker login -u ${REGISTRYUSER} ${REGISTRY}
  fi
  announce $FUNCNAME end
}

install()   # args:        (step 3, the rest are substeps:)
{
  announce $FUNCNAME
  build_images
  if [ $REMOTE -eq 1 ]; then
    transfer_env
    push_images
    onserver pull_images
    onserver server_up
  else
    server_up
  fi
  announce $FUNCNAME end
}

build_images()   # args: 
{
  announce $FUNCNAME
  export BUILD_WHAT=`git log -1 --oneline`
  export BUILD_WHEN=`date --iso=seconds`
  export BUILD_WHO=$(echo `whoami`@`hostname`)
  create_files_on_the_fly
  populate_zz_builddir
  docker-compose build
  announce $FUNCNAME end
}

transfer_env()   # args: 
{
  announce $FUNCNAME
  create_files_on_the_fly
  # Debian Buster has no rsync --mkpath yet, so create path beforehands:
  ssh -t $TUTH  mkdir -p ${ANW}/$ENV_SHORTNAME
  rsync -av --relative anw.sh $DOCKER_COMPOSE_YML $DOCKERENV_ENV $ENVSDIR/*.sh  $TUTH:$ANW/$ENV_SHORTNAME
  announce $FUNCNAME end
}

push_images()   # args: 
{
  announce $FUNCNAME
  push_image django
  push_image postgres
  if [ $DEPLOYMODE != GUNICORN ]; then
    push_image traefik
  fi
  announce $FUNCNAME end
}

push_image()   # args: servicename
{
	docker tag ${untagged}_$1 ${tagged}_$1
	docker push ${tagged}_$1
	docker rmi ${tagged}_$1  # remove tag to avoid cluttering the image list
}

onserver()   # args: other_anw_cmd args...
{
  if [ $REMOTE ]; then
    announce $FUNCNAME
    ssh -t $TUTH  ONSERVER=1 ${ANW}/$ENV_SHORTNAME/anw.sh  $which_env  $@
    announce $FUNCNAME end
  else
    $@
  fi
}

pull_images()   # args: 
{
  announce $FUNCNAME
  pull_image django
  pull_image postgres
  if [ $DEPLOYMODE != GUNICORN ]; then
    pull_image traefik
  fi
  announce $FUNCNAME end
}

pull_image()   # args: servicename
{
	docker pull ${tagged}_$1
	docker tag ${tagged}_$1 ${untagged}_$1
	docker rmi ${tagged}_$1  # remove tag to avoid cluttering the image list
}

server_up()   # args: 
{
  announce $FUNCNAME
  if [ ${ONSERVER:-0} = 0 ]; then
    create_files_on_the_fly
  fi
  docker-compose up --no-build -d
  announce $FUNCNAME end
}

server_down()   # args: 
{
  announce $FUNCNAME
  if [ ! ${ONSERVER:-0} ]; then
    create_files_on_the_fly
  fi
  docker-compose down
  announce $FUNCNAME end
}


# ########## individual command functions (internal):

announce()  # internal: funcname [internal|end]
{
  if [ "$2" == end ]; then
    echo "((((end of $1))))"
  elif [ "$2" == internal ]; then
    echo "## internal: $1"
  else
    echo ""
    echo "########## $1"
  fi
}

check_deploymode()   # internal
{
  if [[ $DEPLOYMODE == "" ]]; then
    echo "DEPLOYMODE is not defined. (Perhaps consult README.md.)"
    exit 1
  elif [[ ! $DEPLOYMODE =~ ^(CERTS|DEVELOPMENT|GUNICORN|LETSENCRYPT)$ ]]; then
    echo "DEPLOYMODE=$DEPLOYMODE. Must be one of: CERTS|DEVELOPMENT|GUNICORN|LETSENCRYPT."
    exit 1
  fi
    
}
completions()   # internal
{
  # use as  $(./anw.sh - completions)
  # https://www.gnu.org/software/bash/manual/bash.html#Programmable-Completion
  wordlist=`egrep '\(\) *[#] args:' $myself | sed 's/().\+//' | tr '\n' ' '` 
  echo complete -W \"$wordlist\" anw.sh
}

create_files_on_the_fly()   # internal
{
  if [ $files_are_created ]; then
    return
  fi
  announce $FUNCNAME internal
  make_dockerenv_env
  if [ $DEPLOYMODE == DEVELOPMENT ]; then
    make_docker_compose_yml_development
  else
    make_docker_compose_yml
  fi
  if [[ $DEPLOYMODE =~ ^(CERTS|LETSENCRYPT)$ ]]; then
    make_traefik_yml
  fi
  files_are_created=1
}

populate_zz_builddir()   # internal
{
  cmd="cp --update"
  target=.zz_builddir
  $cmd CONTRIBUTORS LICENSE README.md RELEASES.md  $target
  $cmd manage.py pytest.ini requirements.txt setup.cfg  $target
  $cmd -R anwesende compose config  $target

}
make_docker_compose_yml()  # internal
{
  # ugly function due to inline documents violating the indentation
  announce $FUNCNAME internal
  cat >$DOCKER_COMPOSE_YML <<ENDOFFILE1
version: '2.1'
# created by anw.sh; do not modify
# https://docs.docker.com/compose/compose-file/

services:
  django:
    env_file: $DOCKERENV_ENV
    build:
      context: ./.zz_builddir
      dockerfile: ./compose/django/Dockerfile
      args:
        - "DJANGO_UID=${DJANGO_UID}"
        - "DJANGO_GID=${DJANGO_GID}"
      labels:
        - "anwesende.build.what=${BUILD_WHAT}"
        - "anwesende.build.when=${BUILD_WHEN}"
        - "anwesende.build.who=${BUILD_WHO}"
    image: anw_${ENV_SHORTNAME}_django
    container_name: c_anw_${ENV_SHORTNAME}_django
    volumes:
      - ${VOLUME_SERVERDIR_DJANGO_LOG}:/djangolog:Z
    depends_on:
      - postgres
    restart: unless-stopped
ENDOFFILE1
  if [ $DEPLOYMODE == GUNICORN ]; then
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE2
    ports:
      - "0.0.0.0:${GUNICORN_PORT}:5000"
ENDOFFILE2
  fi
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE3
    command: /start

  postgres:
    env_file: $DOCKERENV_ENV
    build:
      context: .
      dockerfile: ./compose/postgres/Dockerfile
    image: anw_${ENV_SHORTNAME}_postgres
    container_name: c_anw_${ENV_SHORTNAME}_postgres
    volumes:
      - ${VOLUME_SERVERDIR_POSTGRES_DATA}:/var/lib/postgresql/data:Z
      - ${VOLUME_SERVERDIR_POSTGRES_BACKUP}:/backups:z
    restart: unless-stopped

ENDOFFILE3
  if [ $DEPLOYMODE != GUNICORN ]; then
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE4
  traefik:
    env_file: $DOCKERENV_ENV
    build:
      context: .
      dockerfile: ./compose/traefik/Dockerfile
    image: anw_${ENV_SHORTNAME}_traefik
    container_name: c_anw_${ENV_SHORTNAME}_traefik
    depends_on:
      - django
    restart: unless-stopped
    volumes:
ENDOFFILE4
   fi
  if [ $DEPLOYMODE == LETSENCRYPT ]; then
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE5
      - ${VOLUME_SERVERDIR_TRAEFIK_ACME}:/etc/traefik/acme:z
ENDOFFILE5
  fi
  if [ $DEPLOYMODE == CERTS ]; then
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE6
      - ${VOLUME_SERVERDIR_TRAEFIK_SSL}:/etc/traefik/myssl:z
ENDOFFILE6
  fi
  if [ $DEPLOYMODE != GUNICORN ]; then
    cat >>$DOCKER_COMPOSE_YML <<ENDOFFILE7
    ports:
      - "0.0.0.0:${TRAEFIK_HTTP_PORT}:80"
      - "0.0.0.0:${TRAEFIK_HTTPS_PORT}:443"
ENDOFFILE7
  fi
}  # END make_docker_compose_yml

make_docker_compose_yml_development()  # internal
{
  announce $FUNCNAME internal
  cat >$DOCKER_COMPOSE_YML <<ENDOFFILE
version: '2.1'
# https://docs.docker.com/compose/compose-file/
# created by anw.sh; do not modify

services:
  postgres:
    build:
      context: .
      dockerfile: ./compose/postgres/Dockerfile
    image: anwesende_development_postgres
    container_name: postgres
    ports:
      - "0.0.0.0:${LOCAL_POSTGRES_PORT}:5432"
    volumes:
      - dbstore:/var/lib/postgresql/data:Z
      - dbstore:/backups:z
    env_file:
      - .envs/autogenerated.env
      
volumes:
  dbstore:
ENDOFFILE
}

make_dockerenv_env()  # internal
{
  announce $FUNCNAME internal
  python3 $PATCHENV $MYENV_ENV $DOCKERENV_ENV
}

make_traefik_yml()  # internal
{
  # ugly function due to inline documents violating the indentation
  announce $FUNCNAME internal
  cat >$TRAEFIK_YML <<ENDOFentrypoints
# https://doc.traefik.io/traefik/v2.0/providers/file/
# created by anw.sh; do not modify
# Quote: "Go Templating only works with dedicated dynamic configuration files.
#         Templating does not work in the Traefik main static configuration file."
log:
  level: INFO

entryPoints:
  web:
    # http
    address: ":80"

  web-secure:
    # https
    address: ":443"

ENDOFentrypoints
  if [ $DEPLOYMODE == LETSENCRYPT ]; then
      cat >>$TRAEFIK_YML <<ENDOFcertresolver
certificatesResolvers:
  letsencrypt:
    # https://docs.traefik.io/master/https/acme/#lets-encrypt
    acme:
      email: "$LETSENCRYPTEMAIL"
      storage: /etc/traefik/acme/acme.json
      # https://docs.traefik.io/master/https/acme/#httpchallenge
      httpChallenge:
        entryPoint: web
ENDOFcertresolver
  fi
  echo $TRAEFIK_YML
  cat >>$TRAEFIK_YML <<"ENDOFrouters1"
http:
  routers:
    web-router:
      rule: "PathPrefix(`/`)"
      entryPoints:
        - web
      middlewares:
        - redirect_root
        - redirect_a
        - redirect_fu
        - redirect_to_https
      service: django

    web-secure-router:
      # https://doc.traefik.io/traefik/routing/routers/#rule
ENDOFrouters1
  echo "      rule: \"Host(\`$SERVERNAME\`) && PathPrefix(\`/\`)\""  >>$TRAEFIK_YML
  cat >>$TRAEFIK_YML <<ENDOFrouters2
      entryPoints:
        - web-secure
      # middlewares:
      #   - csrf
      service: django
ENDOFrouters2
  if [ $DEPLOYMODE == LETSENCRYPT ]; then
      cat >>$TRAEFIK_YML <<ENDOFcertresolver2
      tls:
        certResolver: letsencrypt
ENDOFcertresolver2
  elif [ $DEPLOYMODE == CERTS ]; then
      cat >>$TRAEFIK_YML <<ENDOFtlsbare
      tls: {}
ENDOFtlsbare
  fi
  cat >>$TRAEFIK_YML <<"ENDOFredirects"

  middlewares:
    # https://doc.traefik.io/traefik/master/middlewares/overview/
    redirect_root:
      # https://doc.traefik.io/traefik/v2.0/middlewares/redirectregex/
      redirectRegex:
        regex: "^http://a.nwesen.de/?$"
        replacement: "http://anwesende.imp.fu-berlin.de/"
    redirect_a:
      redirectRegex:
        regex: "^http://a.nwesen.de/a/(.*)$"
        replacement: "http://anwesende.imp.fu-berlin.de/${1}"
    redirect_fu:
      redirectRegex:
        regex: "^http://a.nwesen.de/fu/(.*)$"
        replacement: "http://anwesende.imp.fu-berlin.de/${1}"
    redirect_to_https:
      # https://docs.traefik.io/master/middlewares/redirectscheme/
      redirectScheme:
        scheme: https
        permanent: false

  services:
    django:
      loadBalancer:
        servers:
          - url: http://django:5000
tls:
ENDOFredirects
  if [ $DEPLOYMODE == CERTS ]; then
    cat >>$TRAEFIK_YML <<ENDOFcerts
  # https://docs.traefik.io/master/routing/routers/#certresolver
  certificates:
    - certFile: /etc/traefik/myssl/certs/anwesende.pem
      keyFile: /etc/traefik/myssl/private/anwesende-key.pem
ENDOFcerts
  fi
  cat >>$TRAEFIK_YML <<ENDOFoptions
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        # https://ssl-config.mozilla.org/#server=traefik&version=2.1.2&config=intermediate&guideline=5.6
        # https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices#25-use-forward-secrecy
        - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"

providers:
  # https://docs.traefik.io/master/providers/file/
  file:
    filename: /etc/traefik/traefik.yml
    watch: true

ENDOFoptions
}  # END make_traefik_yml


# ########## MAIN:

# set -o xtrace  # -x
set -o errexit  # -e
which_env=$1
cmd=$2
shift 2

cd -P -- "$(dirname -- "$0")"  # cd to script dir if called from elsewhere (ssh!)
myself=`basename $0`

if [ $which_env != '-' -a $which_env != '--' ]; then
  set -o allexport  # -a: export all new shell variables
  source $ENVSDIR/$which_env.sh
  check_deploymode
  set +o allexport
  untagged=${ANW}_${ENV_SHORTNAME}
  tagged=${REGISTRYPREFIX}/${ANW}_${ENV_SHORTNAME}
  announce "Environment is '$which_env'"
fi

$cmd $@
