docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml -f docker-compose.jenkins.yml stop db backend frontend
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml -f docker-compose.jenkins.yml rm -f db backend frontend
docker rm -f qa-runner-e2e
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml -f docker-compose.jenkins.yml up -d db backend frontend
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml -f docker-compose.jenkins.yml build qa-runner
docker compose --env-file .env.qa_fuc -f docker-compose.qa_fuc.yml -f docker-compose.jenkins.yml run --name qa-runner-e2e -e REPORTS_DIR=/qa/reports/fuc -e RUN_NEWMAN=false -e RUN_SONAR=false -e RUN_PLAYWRIGHT=true -e RUN_K6=false qa-runner
