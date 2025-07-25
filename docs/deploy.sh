#!/usr/bin/env bash

set -euo pipefail

scriptdir=$(dirname "${BASH_SOURCE[0]}")
bucket="$AWS_BUCKET"
target="${1-$scriptdir/out}"

if [ ! -d "$target" ]; then
  echo "target $target not found"
  exit 1
fi


# To keep the previous website up and running, we deploy it using these steps.
#   1.  Sync Next.js static assets in \`_next/**\` folder
#      > Uploads the new generated JS and asset files (stored in hashed folders to avoid collision with older deployments)
#   2.  Sync assets in \`static/**\` folder
#   3. Overwrite HTML dependents, not located in \`_next/**\` or \`static/**\` folder
#      > Force overwrite of all HTML files to make sure we use the latest one
#   4. Sync assets and clean up outdated files from previous deployments
#   5. Add custom redirects
#   6. Notify Google of sitemap changes for SEO

echo "::group::[1/6] Sync Next.js static assets in \`_next/**\` folder"
aws s3 sync \
  --no-progress \
  --exclude "*" \
  --include "_next/**" \
  --cache-control "public, max-age=31536000, immutable" \
  "$target" \
  "s3://${bucket}"
echo "::endgroup::"

echo "::group::[2/6] Sync assets in \`static/**\` folder"
aws s3 sync \
  --no-progress \
  --exclude "*" \
  --include "static/**" \
  --cache-control "public, max-age=3600, immutable" \
  "$target" \
  "s3://${bucket}"
echo "::endgroup::"

# Due to a bug with `aws s3 sync` we need to copy everything first instead of syncing
# see: https://github.com/aws/aws-cli/issues/3273#issuecomment-643436849
echo "::group::[3/6] Overwrite HTML dependents, not located in \`_next/**\` or \`static/**\` folder"
aws s3 cp \
  --no-progress \
  --recursive \
  --exclude "_next/**" \
  --exclude "static/**" \
  "$target" \
  "s3://${bucket}"
echo "::endgroup::"

echo "::group::[4/6] Sync assets and clean up outdated files from previous deployments"
aws s3 sync \
  --no-progress \
  --delete \
  "$target" \
  "s3://${bucket}"
echo "::endgroup::"

declare -A redirects # associative array variable

# usage:
# redirects[requests/for/this/path]=are/redirected/to/this/one

# Old redirects
redirects[distribution/building-standalone-apps]=build/setup

# clients is now development
redirects[clients/installation]=versions/latest/sdk/dev-client

# Expo Modules
redirects[modules]=modules/overview
redirects[module-api]=modules/module-api
redirects[module-config]=modules/module-config

# Development builds
redirects[development/build]=develop/development-builds/create-a-build
redirects[development/getting-started]=develop/development-builds/create-a-build
redirects[development/troubleshooting]=develop/development-builds/introduction
redirects[development/upgrading]=develop/development-builds/introduction
redirects[development/extensions]=develop/development-builds/development-workflows
redirects[development/develop-your-project]=develop/development-builds/use-development-builds
redirects[develop/development-builds/installation]=develop/development-builds/create-a-build

# Guides that have been deleted
redirects[guides/web-performance]=guides/analyzing-bundles
redirects[push-notifications/obtaining-a-device-token-for-fcm-or-apns]=push-notifications/sending-notifications-custom

# Redirects after adding Home to the docs
redirects[next-steps/additional-resources]=additional-resources
redirects[get-started/create-a-new-app]=get-started/create-a-project
redirects[guides/config-plugins]=config-plugins/introduction
redirects[workflow/debugging]=debugging/runtime-issues
redirects[workflow/expo-go]=get-started/set-up-your-environment
redirects[guides/splash-screens]=develop/user-interface/splash-screen
redirects[guides/app-icons]=develop/user-interface/app-icons
redirects[guides/color-schemes]=develop/user-interface/color-themes
redirects[development/introduction]=develop/development-builds/introduction
redirects[development/create-development-builds]=develop/development-builds/create-a-build
redirects[development/use-development-builds]=develop/development-builds/use-development-builds
redirects[development/development-workflows]=develop/development-builds/development-workflows
redirects[debugging]=debugging/runtime-issues
redirects[debugging/runtime-issue]=debugging/runtime-issues
redirects[develop/development-builds/parallel-installation]=build-reference/variants
redirects[guides/assets]=develop/user-interface/assets

# Redirects after Guides organization
redirects[guides]=guides/overview
redirects[guides/routing-and-navigation]=routing/introduction
redirects[guides/errors]=debugging/runtime-issues
redirects[workflow/expo-cli]=more/expo-cli
redirects[versions/latest/workflow/expo-cli]=more/expo-cli
redirects[bare/hello-world]=bare/overview
redirects[guides/using-graphql]=guides/overview
redirects[build/automating-submissions]=build/automate-submissions
redirects[workflow/run-on-device]=build/internal-distribution
redirects[archive/workflow/customizing]=workflow/customizing
redirects[guides/building-standalone-apps]=build/setup
redirects[versions/latest/sdk/permissions]=guides/permissions
redirects[push-notifications/using-fcm]=push-notifications/push-notifications-setup

# Redirects reported from SEO tools list (MOZ, SEMRush, GSC, etc.)
redirects[bare/installing-unimodules]=bare/installing-expo-modules
redirects[versions/latest/sdk/admob]=versions/latest
redirects[workflow/publishing]=archive/classic-updates/publishing
redirects[workflow/already-used-react-native]=workflow/overview
redirects[development/installation]=develop/development-builds/create-a-build
redirects[bare/updating-your-app]=eas-update/getting-started
redirects[technical-specs/expo-updates-0]=technical-specs/expo-updates-1
redirects[archive/expokit/eject]=archive/glossary
redirects[archive/expokit/overview]=archive/glossary
redirects[expokit/overview]=archive/glossary
redirects[bare/existing-apps]=bare/installing-expo-modules
redirects[bare/exploring-bare-workflow]=bare/overview
redirects[build-reference/custom-build-config]=custom-builds/get-started
redirects[build-reference/how-tos]=build-reference/private-npm-packages
redirects[eas-update/migrate-codepush-to-eas-update]=eas-update/codepush
redirects[guides/testing-on-devices]=build/internal-distribution
redirects[technical-specs/latest]=technical-specs/expo-updates-1

# We should change this redirect to a more general EAS guide later
redirects[guides/setting-up-continuous-integration]=build/building-on-ci

# Moved classic updates
redirects[distribution/release-channels]=archive/classic-updates/release-channels
redirects[distribution/advanced-release-channels]=archive/classic-updates/advanced-release-channels
redirects[distribution/optimizing-updates]=archive/classic-updates/optimizing-updates
redirects[distribution/runtime-versions]=eas-update/runtime-versions
redirects[guides/offline-support]=archive/classic-updates/offline-support
redirects[guides/preloading-and-caching-assets]=archive/classic-updates/preloading-and-caching-assets
redirects[guides/configuring-updates]=archive/classic-updates/configuring-updates
redirects[eas-update/bare-react-native]=eas-update/getting-started
redirects[worfkflow/publishing]=archive/classic-updates/publishing
redirects[classic/building-standalone-apps]=build/setup
redirects[classic/turtle-cli]=build/setup
redirects[archive/classic-updates/getting-started]=eas-update/getting-started
redirects[archive/classic-updates/building-standalone-apps]=build/setup

# EAS Update
redirects[eas-update/developing-with-eas-update]=eas-update/develop-faster
redirects[eas-update/eas-update-with-local-build]=eas-update/standalone-service
redirects[eas-update/eas-update-and-eas-cli]=eas-update/eas-cli
redirects[eas-update/debug-updates]=eas-update/debug
redirects[eas-update/how-eas-update-works]=eas-update/how-it-works
redirects[eas-update/migrate-to-eas-update]=eas-update/migrate-from-classic-updates
redirects[eas-update/custom-updates-server]=versions/latest/sdk/updates
redirects[distribution/custom-updates-server]=versions/latest/sdk/updates
redirects[bare/error-recovery]=eas-update/error-recovery
redirects[deploy/instant-updates]=eas-update/send-over-the-air-updates
redirects[eas-update/publish]=eas-update/getting-started
redirects[eas-update/debug-advanced]=eas-update/debug
redirects[eas-update/develop-faster]=eas-update/preview

# Redirects for Expo Router docs
redirects[routing/next-steps]=router/introduction
redirects[routing/introduction]=router/introduction
redirects[routing/installation]=router/installation
redirects[routing/create-pages]=router/create-pages
redirects[routing/navigating-pages]=router/navigating-pages
redirects[routing/layouts]=router/basics/layout
redirects[routing/appearance]=router/introduction
redirects[routing/error-handling]=router/error-handling
redirects[router/advance/root-layout]=router/basics/layout/#root-layout
redirects[router/advance/stack]=router/advanced/stack
redirects[router/advance/tabs]=router/advanced/tabs
redirects[router/advance/drawer]=router/advanced/drawer
redirects[router/advance/nesting-navigators]=router/advanced/nesting-navigators
redirects[router/advance/modal]=router/advanced/modals
redirects[router/advance/platform-specific-modules]=router/advanced/platform-specific-modules
redirects[router/reference/platform-specific-modules]=router/advanced/platform-specific-modules
redirects[router/advance/shared-routes]=router/advanced/shared-routes
redirects[router/advance/router-setttings]=router/advanced/router-settings
redirects[router/reference/search-parameters]=router/reference/url-parameters
redirects[router/appearance]=router/introduction

# Removed API reference docs
redirects[versions/latest/sdk/facebook]=guides/authentication
redirects[versions/latest/sdk/taskmanager]=versions/latest/sdk/task-manager
redirects[versions/latest/sdk/videothumbnails]=versions/latest/sdk/video-thumbnails
redirects[versions/latest/sdk/appearance]=versions/latest/react-native/appearance
redirects[versions/latest/sdk/app-loading]=versions/latest/sdk/splash-screen
redirects[versions/latest/sdk/app-auth]=guides/authentication
redirects[versions/latest/sdk/firebase-core]=guides/using-firebase
redirects[versions/latest/sdk/firebase-analytics]=guides/using-firebase
redirects[versions/latest/sdk/firebase-recaptcha]=guides/using-firebase
redirects[versions/latest/sdk/google-sign-in]=guides/authentication
redirects[versions/latest/sdk/google]=guides/authentication
redirects[versions/latest/sdk/amplitude]=guides/using-analytics
redirects[versions/latest/sdk/util]=versions/latest
redirects[versions/latest/introduction/faq]=faq
redirects[versions/latest/sdk/in-app-purchases]=guides/in-app-purchases/

# Redirects based on Sentry reports
redirects[push-notifications]=push-notifications/overview
redirects[eas/submit]=submit/introduction
redirects[development/tools/expo-dev-client]=develop/development-builds/introduction
redirects[develop/user-interface/custom-fonts]=develop/user-interface/fonts
redirects[workflow/snack]=more/glossary-of-terms
redirects[accounts/teams-and-accounts]=accounts/account-types
redirects[push-notifications/fcm]=push-notifications/sending-notifications-custom
redirects[troubleshooting/clear-cache-mac]=troubleshooting/clear-cache-macos-linux
redirects[guides/using-preact]=guides/overview
redirects[versions/latest/sdk/shared-element]=versions/latest
redirects[workflow/hermes]=guides/using-hermes

# Redirects based on Algolia 404 report
redirects[workflow/build/building-on-ci]=build/building-on-ci
redirects[versions/v52.0.0/sdk/taskmanager]=versions/v52.0.0/sdk/task-manager
redirects[versions/v51.0.0/sdk/taskmanager]=versions/v51.0.0/sdk/task-manager
redirects[task-manager]=versions/latest/sdk/task-manager
redirects[versions/latest/sdk/filesystem.md]=versions/latest/sdk/filesystem
redirects[guides/how-expo-works]=faq
redirects[config/app]=workflow/configuration
redirects[guides/authentication.md]=guides/authentication
redirects[versions/latest/workflow/linking]=guides/linking
redirects[versions/latest/sdk/overview]=versions/latest

# Deprecated webpack
redirects[guides/customizing-webpack]=archive/customizing-webpack

# May 2024 home / get started section
redirects[overview]=get-started/introduction
redirects[get-started/installation]=get-started/create-a-project
redirects[get-started/expo-go]=get-started/set-up-your-environment

# Redirect for /learn URL
redirects[learn]=tutorial/introduction

# May 2024 home / develop section
redirects[develop/user-interface/app-icons]=develop/user-interface/splash-screen-and-app-icon
redirects[develop/user-interface/splash-screen]=develop/user-interface/splash-screen-and-app-icon

# Preview section
redirects[preview/support]=preview/introduction
redirects[preview/react-compiler]=guides/react-compiler

# Archived
redirects[guides/using-flipper]=debugging/tools

# Troubleshooting section
redirects[guides/troubleshooting-proxies]=troubleshooting/proxies

# After adding "Linking" (/linking/**) section
redirects[guides/linking]=linking/overview
redirects[guides/deep-linking]=linking/into-your-app

# After adding /sdk/router/ API reference
redirects[router/reference/hooks]=versions/latest/sdk/router

# After moving custom tabs under Expo Router > Navigation patterns
redirects[router/ui/tabs]=router/advanced/custom-tabs

# After new environment variables guide
redirects[build-reference/variables]=eas/environment-variables
redirects[eas-update/environment-variables]=eas/environment-variables

# After moving common questions from Expo Router FAQ to Introduction
redirects[router/reference/faq]=router/introduction

# After migrating Prebuild page info to CNG page
redirects[workflow/prebuild]=workflow/continuous-native-generation

# After removing UI programming section
redirects[ui-programming/image-background]=tutorial/overview
redirects[ui-programming/implementing-a-checkbox]=versions/latest/sdk/checkbox
redirects[ui-programming/z-index]=tutorial/overview
redirects[ui-programming/using-svgs]=versions/latest/sdk/svg
redirects[ui-programming/react-native-toast]=tutorial/overview
redirects[ui-programming/react-native-styling-buttons]=tutorial/overview
redirects[ui-programming/user-interface-libraries]=tutorial/overview

# After renaming "workflows" to "eas-workflows"
redirects[workflows/get-started]=eas/workflows/get-started
redirects[workflows/triggers]=eas/workflows/syntax/#on
redirects[workflows/jobs]=eas/workflows/syntax/#jobs
redirects[workflows/control-flow]=eas/workflows/syntax/#control-flow
redirects[workflows/variables]=eas/workflows/syntax/#jobsjob_idoutputs

# After moving eas-workflows to eas/workflows
redirects[eas-workflows/get-started]=eas/workflows/get-started
redirects[eas-workflows/triggers]=eas/workflows/syntax/#on
redirects[eas-workflows/jobs]=eas/workflows/syntax/#jobs
redirects[eas-workflows/control-flow]=eas/workflows/syntax/#control-flow
redirects[eas-workflows/variables]=eas/workflows/syntax/#jobsjob_idoutputs
redirects[eas-workflows/upgrade]=eas/workflows/automating-eas-cli
redirects[eas/workflows/upgrade]=eas/workflows/automating-eas-cli

# After moving eas/workflows/examples to eas/workflows/examples/*
redirects[eas/workflows/examples]=eas/workflows/examples/introduction
redirects[eas/workflows/examples/#development-builds-workflow]=eas/workflows/examples/create-development-builds
redirects[eas/workflows/examples/#preview-updates-workflow]=eas/workflows/examples/publish-preview-update
redirects[eas/workflows/examples/#deploy-to-production-workflow]=eas/workflows/examples/deploy-to-production
redirects[eas/workflows/reference/e2e-tests]=eas/workflows/examples/e2e-tests

# After moving e2e-tests to eas/workflows/reference
redirects[build-reference/e2e-tests]=eas/workflows/examples/e2e-tests

# After adding distribution section under EAS
redirects[distribution/publishing-websites]=guides/publishing-websites

# Based on Google Search Console not found report 2025-01-02
redirects[versions/latest/sdk/sqlite-next]=versions/latest/sdk/sqlite
redirects[versions/latest/sdk/camera-next]=versions/latest/sdk/camera
redirects[home/overview]=/
redirects[develop/project-structure]=get-started/start-developing
redirects[versions/latest/sdk/bar-code-scanner]=versions/latest/sdk/camera
redirects[bare/using-expo-client]=bare/install-dev-builds-in-bare
redirects[versions/latest/sdk/sqlite-legacy]=versions/latest/sdk/sqlite
redirects[versions/latest/config/app/name]=versions/latest/config/app/#name
redirects[bare]=bare/overview
redirects[accounts/working-together]=accounts/account-types
redirects[versions/latest/sdk/random]=versions/latest/sdk/crypto
redirects[eas-update/known-issues]=eas-update/introduction

# After consolidating the "Internal distribution" information
redirects[guides/sharing-preview-releases]=build/internal-distribution

# After merging EAS environment variables guides
redirects[eas/using-environment-variables]=eas/environment-variables

# After Expo Router Getting Started Guide
redirects[router/reference/authentication]=router/advanced/authentication
redirects[router/advanced/root-layout]=router/basics/layout/#root-layout
redirects[router/reference/not-found]=router/error-handling
redirects[router/navigating-pages]=router/basics/navigation
redirects[router/create-pages]=router/basics/core-concepts

# After updating config plugin section
redirects[config-plugins/plugins-and-mods]=config-plugins/plugins

# After merging registerRootComponent info in `expo` API reference
redirects[versions/v53.0.0/sdk/register-root-component]=versions/latest/sdk/expo/#registerrootcomponentcomponent
redirects[versions/v53.0.0/sdk/url]=versions/v53.0.0/sdk/expo/#url-api
redirects[versions/v53.0.0/sdk/encoding]=versions/v53.0.0/sdk/expo/#encoding-api

# After adding System bars
redirects[guides/configuring-statusbar]=develop/user-interface/system-bars

# After changing "Privacy Shield" to "Data Privacy Framework" and deleting Privacy Shield page
redirects[regulatory-compliance/privacy-shield]=regulatory-compliance/data-and-privacy-protection

echo "::group::[5/6] Add custom redirects"
for i in "${!redirects[@]}" # iterate over keys
do
  aws s3 cp \
    --no-progress \
    --cache-control "public, max-age=86400" \
    --metadata-directive REPLACE \
    --website-redirect "/${redirects[$i]}" \
    "$target/404.html" \
    "s3://${bucket}/${i}"

  # Also add redirects for paths without `.html` or `/`
  # S3 translates URLs with trailing slashes to `path/` -> `path/index.html`
  if [[ $i != *".html" ]] && [[ $i != *"/" ]]; then
    aws s3 cp \
      --no-progress \
      --cache-control "public, max-age=86400" \
      --metadata-directive REPLACE \
      --website-redirect "/${redirects[$i]}" \
      "$target/404.html" \
      "s3://${bucket}/${i}/index.html"
  fi
done
echo "::endgroup::"

# Set the S3 bucket properties including default error page, which is 404.html
# You can see those settings inside AWS dashboard in "Properties" -> "Static website hosting"
echo "::group::[6/6] Setting bucket properties"
aws s3 website s3://${bucket}/ \
  --index-document index.html \
  --error-document 404.html
echo "::endgroup::"
