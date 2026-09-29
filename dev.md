# useful commands
## clean up docker
use it when docker says "There is no space left on device". It will remove built but not used images and other temporary files.
```
docker system prune -f
```

```
docker rm -f $(docker ps -qa)
```

## build container with no cache
```
docker-compose build --no-cache --progress=plain
```

## what `docker compose build; docker compose up -d` brings and resets

Nothing manual after a rebuild — the build carries everything the app needs:

- the module (loaded by `iris.script`), the canvas (`/opt/sentai-web`) and the semantic-search
  provider row (`sentai-steps` → `sentai.search.LocalEmbedding`, in-process) are baked into the
  image;
- so are the search's Python packages (`/usr/irissys/mgr/python`, CPU-only torch) and its model
  (`/usr/irissys/mgr/sentai-models`, `all-MiniLM-L6-v2`); the image sets `HF_HUB_OFFLINE=1` and
  `TRANSFORMERS_OFFLINE=1`, so nothing is downloaded at run time;
- the image's command starts the search worker (`sentai.search.EmbeddingWorker`, one process,
  ≈450 MB) right after IRIS starts; it is ready about seven seconds after the container is healthy.
  Check it with `##class(sentai.search.EmbeddingWorker).State()` in an `iris session` (`ready`), and
  the whole setup with `bash scripts/check-search-image.sh`.

**Coming from a stack built before spec 017** (with an `ollama` service): rebuild, `docker compose
up -d --build --remove-orphans`. Without `--build` the old image's row still points at `ollama`, and
intent search answers `unreachable` (the palette keeps its local filter). The leftover
`ollama-models` volume and `ollama/ollama` image are no longer used and can be removed.

What is **not** durable: IRISAPP's runtime data (flows, runs, targets) — the compose file mounts no
IRIS data volume, so a rebuild starts a fresh database. The semantic-search corpus is a cache and
rebuilds itself on the first search after the stack comes up (a few seconds, once).
## start iris container
```
docker-compose up -d
```

## open iris terminal in docker
```
docker exec iris iris session iris -U IRISAPP
```


## import objectscirpt code

do $System.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1)
## map iris key from Mac home directory to IRIS in container
- ~/iris.key:/usr/irissys/mgr/iris.key

## install git in the docker image
## add git in dockerfile
USER root
RUN apt update && apt-get -y install git

USER ${ISC_PACKAGE_MGRUSER}


## install docker-compose
```
sudo curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

```

## load and test module
```

zpm "load /home/irisowner/dev"

zpm "test dc-sample"
```

## select zpm test registry
```
repo -n registry -r -url https://test.pm.community.intersystems.com/registry/ -user test -pass PassWord42
```

## get back to public zpm registry
```
repo -r -n registry -url https://pm.community.intersystems.com/ -user "" -pass ""
```

## export a global in runtime into the repo
```
d $System.OBJ.Export("GlobalD.GBL","/irisrun/repo/src/gbl/GlobalD.xml")
```

## create a web app in dockerfile
```
zn "%SYS" \
  write "Create web application ...",! \
  set webName = "/csp/irisweb" \
  set webProperties("NameSpace") = "IRISAPP" \
  set webProperties("Enabled") = 1 \
  set webProperties("CSPZENEnabled") = 1 \
  set webProperties("AutheEnabled") = 32 \
  set webProperties("iKnowEnabled") = 1 \
  set webProperties("DeepSeeEnabled") = 1 \
  set sc = ##class(Security.Applications).Create(webName, .webProperties) \
  write "Web application "_webName_" has been created!",!
```



```
do $SYSTEM.OBJ.ImportDir("/opt/irisbuild/src",, "ck")
```


### run tests described in the module

IRISAPP>zpm
IRISAPP:zpm>load /irisrun/repo
IRISAPP:zpm>test package-name

### install ZPM with one line
    // Install ZPM
    set $namespace="%SYS", name="DefaultSSL" do:'##class(Security.SSLConfigs).Exists(name) ##class(Security.SSLConfigs).Create(name) set url="https://pm.community.intersystems.com/packages/zpm/latest/installer" Do ##class(%Net.URLParser).Parse(url,.comp) set ht = ##class(%Net.HttpRequest).%New(), ht.Server = comp("host"), ht.Port = 443, ht.Https=1, ht.SSLConfiguration=name, st=ht.Get(comp("path")) quit:'st $System.Status.GetErrorText(st) set xml=##class(%File).TempFilename("xml"), tFile = ##class(%Stream.FileBinary).%New(), tFile.Filename = xml do tFile.CopyFromAndSave(ht.HttpResponse.Data) do ht.%Close(), $system.OBJ.Load(xml,"ck") do ##class(%File).Delete(xml)




docker run --rm --name iris-sql -d -p 9091:1972 -p 9092:52773  -e IRIS_PASSWORD=demo -e IRIS_USERNAME=demo intersystemsdc/iris-community


docker run --rm --name iris-ce -d -p 9091:1972 -p 9092:52773 -e IRIS_PASSWORD=demo -e IRIS_USERNAME=demo intersystemsdc/iris-community -a "echo 'zpm \"install webterminal\"' | iriscli"



docker run --rm --name iris-sql -d -p 9092:52773 containers.intersystems.com/intersystems/iris-community:2023.1.0.229.0


docker run --rm --name iris-ce -d -p 9092:52773 containers.intersystems.com/intersystems/iris-community:2023.1.0.229.0