1. Doormat
	request temp GCP account
	acccount ID for DNS (can use the other if you chose wrong, but requires a change 
	can take about 10 minutes

2. Variables.tf
	update project ID
	update zone
	update license
	All other defaults should work

4. Terminal
	gcloud auth application-default login
	gcloud components install gke-gcloud-auth-plugin + path stuff if needed
	terraform init
	terraform plan
	terraform apply

6. deploy-tfe.sh

7. validate-tfe.sh

Troubleshooting

1. zone not found
    you didn't update both the account-ID and zone details

