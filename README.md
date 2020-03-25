# cf-traefik-buildpack

Cloudfoundry buildpack to run [traefik](https://docs.traefik.io/)

## Using it

Deploy the example `manifest.yml`: 

```manifest.yml
---
applications:
- name: traefik
  memory: 512M
  instances: 1
  stack: cflinuxfs3
  random-route: true
  buildpacks:
  - https://github.com/SpringerPE/cf-traefik-buildpack.git
  env:
    ADMIN_AUTH_PASSWORD: hola
    ADMIN_AUTH_USER: admin
#   PORT_INTERNAL
#   ADMIN_HOST: "admin.springernature.app"
#   ADMIN_PROMETHEUS: "1"
```

and go to `https:<route>/dashboard`, use the default credentials.

If you want to see an example service, have a look at `test-app` folder and
run `curl https:<route>/open` or `curl https:<route>/auth`.


### Environment variables

The API/Dashboard web service always requires authentication. If **ADMIN_AUTH_USER** is not defined,
it defaults to `admin` and **ADMIN_AUTH_PASSWORD** will be autogenerated and printed
in stdout (you can see it with `cf logs`) and stored in
`/home/vcap/auth/${ADMIN_AUTH_USER}.password`

* **ADMIN_PREFIX** route path for api, dashboard and/or metrics endpoints, defaults to ``.
*(It seems does not work changing api and dashboard paths)*.
* **ADMIN_HOST** is the hostname from where `/api` and `/dashboard` are being served, by
default is the first hostame assigned to the app.
* **ADMIN_PROMETHEUS** enables/disables prometheus `/metrics` endpoint in `$ADMIN_HOST`.
* **PORT_INTERNAL** if 0, it disables all `/api`, `/metrics` and `/dashboard`, 
otherwise those will run only in this port, and if the variable is not defined,
it runs those endpoints in the default **$PORT**.

Traefik version can be specificed in a `runtime.txt` file or by defining the variable
**VERSION_TRAEFIK** and the url can be defined with the env variable **DOWNLOAD_URL_TRAEFIK**.

# Development

Buildpack implemented using bash scripts to make it easy to understand and change.

https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html

The builpack uses the `deps` and `cache` folders according the implementation purposes,
so, the first time the buildpack is used it will download all resources, next times 
it will use the cached resources.


# Author

(c) 2020 Jose Riguera Lopez  <jose.riguera@springernature.com>
Springernature Engineering Enablement

MIT License
