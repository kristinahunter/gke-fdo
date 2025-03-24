1. Doormat
	request temp GCP account
	acccount ID for DNS (can use the other if you chose wrong, but requires a change 
	can take about 10 minutes

2. Variables.tf
	update project ID
	update zone
	All other defaults should work

3. Terminal
	gcloud auth application-default login
	terraform init
	terraform plan
	terraform apply

4. deploy-tfe.sh

5. validate-tfe.sh

Troubleshooting

1. zone not found
    you didn't update both the account-ID and zone details

