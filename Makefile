GEMSPEC=$(shell ls *.gemspec)
VERSION=$(shell ruby -rrubygems -e 'puts Gem::Specification.load("ftw.gemspec").version')
NAME=$(shell awk -F\" '/spec.name/ { print $$2 }' $(GEMSPEC))
GEM=$(NAME)-$(VERSION).gem

.PHONY: test
test:
	sh notify-failure.sh ruby test/all.rb

.PHONY: testloop
testloop:
	while true; do \
		$(MAKE) test; \
		$(MAKE) wait-for-changes; \
	done

.PHONY: serve-coverage
serve-coverage:
	cd coverage; python -mSimpleHTTPServer

.PHONY: wait-for-changes
wait-for-changes:
	-inotifywait --exclude '\.swp' -e modify $$(find $(DIRS) -name '*.rb'; find $(DIRS) -type d)

certs/cacert.pem:
	wget -O certs/cacert.pem http://curl.haxx.se/ca/cacert.pem

.PHONY: package
package: | $(GEM)

.PHONY: gem
gem: $(GEM)

$(GEM):
	gem build $(GEMSPEC)

.PHONY: test-package
test-package: $(GEM)
	# Sometimes 'gem build' makes a faulty gem.
	gem unpack $(GEM)
	rm -rf ftw-$(VERSION)/

.PHONY: publish
publish: test-package
	gem push $(GEM)

.PHONY: install
install: $(GEM)
	gem install $(GEM)
