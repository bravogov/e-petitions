# An immutable candidate of the original alphagov/e-petitions application.
# The verified upstream base image was installed for the live service.
# Rebuild from this exact base digest, never the mutable release tag.
FROM uhparliament/e-petitions@sha256:8b46305f42e74bc01ce574e5db987a0609ec862e90d4a96a970670d1c25bdbd7
ARG SOURCE_REVISION
ARG UPSTREAM_REVISION=a4912c989279f9ffe39c8f6c51658d29d2b5a9ab
LABEL org.opencontainers.image.title="United Hampshire Parliament petitions" \
      org.opencontainers.image.source="alphagov/e-petitions (UH parliamentary adaptation)" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      uk.parliament.upstream.revision="${UPSTREAM_REVISION}"
WORKDIR /app

# Only original application files are changed. No data, secrets or infrastructure.
COPY app/controllers/archived/petitions_controller.rb app/controllers/archived/petitions_controller.rb
COPY app/views/archived/petitions/index.html.erb app/views/archived/petitions/index.html.erb
COPY app/views/application/_header.html.erb app/views/application/_header.html.erb
COPY app/views/application/_footer.html.erb app/views/application/_footer.html.erb
COPY app/views/layouts/editor.html.erb app/views/layouts/editor.html.erb
COPY app/views/layouts/default_mail.html.erb app/views/layouts/default_mail.html.erb
COPY app/views/layouts/default_mail.text.erb app/views/layouts/default_mail.text.erb
COPY app/assets/stylesheets/frontend/components/_footer.scss app/assets/stylesheets/frontend/components/_footer.scss
COPY config/locales/metadata.en-GB.yml config/locales/metadata.en-GB.yml
COPY config/locales/page_titles.en-GB.yml config/locales/page_titles.en-GB.yml
COPY public/uh-parliament-brand/uh-parliament-logo.png public/uh-parliament-brand/uh-parliament-logo.png

# Update only the original Rails compiled CSS/asset manifest. The approved
# artwork is served directly from public, with exact bytes preserved.
RUN test -n "$SOURCE_REVISION" \
 && STORAGE_ADAPTER=test SECRET_KEY_BASE_DUMMY=1 \
    EPETITIONS_HOST=petition.parliament.uhrblx.com \
    MODERATE_HOST=moderate.petition.parliament.uhrblx.com \
    bundle exec rails css:build \
 && STORAGE_ADAPTER=test SECRET_KEY_BASE_DUMMY=1 \
    EPETITIONS_HOST=petition.parliament.uhrblx.com \
    MODERATE_HOST=moderate.petition.parliament.uhrblx.com \
    bundle exec rails assets:precompile

# This image is an unactivated candidate. Deployment must preserve the original
# native Rails database, workers, site and House-approved feature flags.
