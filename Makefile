default: build

clean:
	docker rmi bborbe/openldap

build:
	docker build --no-cache --rm=true -t bborbe/openldap .

run:
	docker run -h example.com -p 389:389 -p 636:636 bborbe/openldap:latest

shell:
	docker run -i -t bborbe/openldap:latest /bin/bash

upload:
	docker push bborbe/openldap
