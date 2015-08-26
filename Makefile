.PHONY: site push

all: site

site:
	jekyll build

push:
	git add .
	git commit -m "blog update"
	git push origin master
