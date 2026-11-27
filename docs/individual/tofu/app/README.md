# Individual work: AMI + Auto Scaling release

This stack is the release path required by the assignment: the new version is
an AMI, and the application runs in an Auto Scaling group behind an Application
Load Balancer.

1. Update the source instance `timecapsule-dev-app`, remove `DB_PASSWORD` from
   `/var/www/timecapsule/.env`, add `DB_SECRET_ARN`, and verify:

   ```sh
   php bin/check-secret.php
   curl -fsS http://127.0.0.1/health
   ```

2. Build the image (the source instance may reboot):

   ```sh
   cd ../image
   tofu init
   tofu apply -var='ami_name=timecapsule-dev-app-individual-20261127'
   tofu output ami_id
   ```

3. Launch the fleet with the same AMI name:

   ```sh
   cd ../app
   tofu init
   tofu apply -var='run_fleet=true' -var='ami_name=timecapsule-dev-app-individual-20261127'
   tofu output alb_dns
   curl -fsS "http://$(tofu output -raw alb_dns)/health"
   ```

4. After collecting screenshots and logs, remove the chargeable fleet:

   ```sh
   tofu apply -var='run_fleet=false' -var='ami_name=timecapsule-dev-app-individual-20261127'
   ```

The launch template uses `health_check_type = "EC2"` on purpose. The ALB stops
routing to a target whose `/health` fails, but the ASG does not replace it in a
loop while the Secrets Manager policy is broken during the B4 exercise.
