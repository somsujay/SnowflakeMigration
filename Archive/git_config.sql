CREATE OR REPLACE SECRET ssom_git_secret
  TYPE = password
  USERNAME = 'sujaysom'
  PASSWORD = '<github_pat_..................>';

CREATE OR REPLACE API INTEGRATION ssom_github_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.ibm.com')
  ALLOWED_AUTHENTICATION_SECRETS = (ssom_git_secret)
  ENABLED = TRUE;

#This new Git Repo
CREATE GIT REPOSITORY MigrateToSnowflake 
    ORIGIN = 'https://github.ibm.com/sujaysom/MigrateToSnowflake.git' 
	API_INTEGRATION = 'SSOM_GITHUB_INTEGRATION' 
	GIT_CREDENTIALS = 'SSOM_COCO_DB.PUBLIC.SSOM_GIT_SECRET';