.PHONY: build test app run install demo clean

# Build the debug binary.
build:
	swift build

test:
	swift test

# Assemble the signed .app bundle (LSUIElement, launch-at-login capable).
app:
	@./Scripts/bundle.sh

# Run the bundled app.
run: app
	@open ".build/Synqit Notch.app"

install: app
	@rm -rf "/Applications/Synqit Notch.app"
	@cp -R ".build/Synqit Notch.app" /Applications/
	@echo "Installed to /Applications/Synqit Notch.app"
	@echo "Now run \`synqit notch\` from your repo to attach it."

# Fire one escalation at the notch without spending a push or an API call.
# Run `synqit notch` first, and have the app running.
demo:
	@cd .. && jac run tools/notch_demo.jac

clean:
	swift package clean
	@rm -rf ".build/Synqit Notch.app"
