# Example CTM Lambda Repo

This repo is a demo of using git repo to manage a CTM Lambda function from the cli


We rely on 2 git hooks

pre-commit: 
  this will validate and verify a few things about your package before it is commited

post-push:
  when you push to one of the following branches release-production, release-staging, or release-development
  information as you have versioned in config.yml will be uploaded via API to the specific instance of CTM and
  provision your new code

# dependencies

python3 -m venv env

./env/bin/pip3 -r requirements.txt

build installer

Mac OSX installer
```
pyinstaller --onefile  ctm --osx-entitlements-file entitlements.plist
security find-identity -p basic -v
codesign --deep --force --options=runtime --entitlements ./entitlements.plist --sign  656DA... --timestamp ./dist/ctm
```

