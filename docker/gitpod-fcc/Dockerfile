FROM gitpod/workspace-mongodb:latest

LABEL org.opencontainers.image.source=https://github.com/freecodecamp/infra
LABEL org.opencontainers.image.description="A Gitpod image for the freeCodeCamp.org main repo."
LABEL org.opencontainers.image.licenses=BSD-3-Clause

RUN sudo install-packages \
  # Core system libraries
  ca-certificates libc6 libgcc1 libstdc++6 \
  # X11 and graphics libraries
  libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 \
  libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libgbm1 libgles2 \
  # GTK and related libraries
  libatk1.0-0 libatk-bridge2.0-0 libappindicator3-1 \
  libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
  # Font and text rendering
  fonts-liberation libfontconfig1 libharfbuzz-icu0 libwoff1 \
  # Audio and video
  libvpx7 libopus0 libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  # Miscellaneous libraries
  libcups2 libdbus-1-3 libexpat1 libglib2.0-0 libnspr4 \
  libenchant-2-2 libsecret-1-0 libhyphen0 libmanette-0.2-0 libflite1 \
  # Utilities
  lsb-release wget xdg-utils

# from https://www.gitpod.io/docs/introduction/languages/javascript#node-versions
RUN bash -c 'VERSION="20" \
  && source $HOME/.nvm/nvm.sh && nvm install $VERSION \
  && nvm use $VERSION && nvm alias default $VERSION \
  && npm i -g pnpm@9'

RUN echo "nvm use default &>/dev/null" >> ~/.bashrc.d/51-nvm-fix

RUN npx -y playwright install
