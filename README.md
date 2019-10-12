# Census 2016 Demo

This is a demo of using cancensus to analyze housing value in Metro Vancouver. There is a docker image of the environment that was used to create this analysis, which you are free to use.

## Getting started

1. Install the required software

You will need to have Docker installed to use the docker image. Alternatively, you can set up your working environment with R, RStudio, git and RMarkdown, etc.

2. Pull the latest image from docker

`docker pull bowenwen\dockerrstudio:latest`

3. Start the docker container

`docker run --rm --name temp_dockerrstudio --env PASSWORD=test -p 8787:8787 bowenwen\dockerrstudio:latest`

You can set your own password and/or add `--volume $pwd:/home/rstudio` to the docker run command to link a folder between your host OS and the docker container.

4. Pull the latest Census 2016 demo code from GitHub

`git clone https://github.com/bowenwen/can_census.git`

5. Now you are ready to explore and play with this demo analysis