# resume-as-code
## azure-bootstrap readme
### purpose
terraform can only run if it has a account to authenticate to your cloud provider with.  in addition, in order for terraform to store its state data, and subsequently retain any state information desired from one execution of terraform to the next, it requires some kind of storage for its state.

the azure-bootstrap.ps1 powershell script, creates the prerequsite resources for you, assigns the desired permissions/roles and then outputs the results in your terminal to be added into your terraform configurations.

### execution
the powershell script is parameterized if you want to provide any values at runtime, but since this is generally a one-time execute situation, I prefer leveraging the default values when they are not sensitive.

I think the easiest way to run this is:
1. view the azure-bootstrap.ps1 file, ctrl+a and copy.
2. login to your azure portal (with an account with appropriate access)
3. open your azure cloud shell in powershell mode and run:
    - ``code bootstrap.ps1``
4. in the editor, paste your code, and save (ctrl+s).
5. in the terminal execute via:
    - ``./bootstrap.ps1``