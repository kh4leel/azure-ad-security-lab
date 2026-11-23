<#
  New-LabUsers.ps1  -  Khaleel's AD lab
  Builds the OU structure, department security groups, and 55 users (11 per dept).
  Run on DC01 as a Domain Admin:  powershell -ExecutionPolicy Bypass -File .\New-LabUsers.ps1
#>
Import-Module ActiveDirectory

$DomainDN   = (Get-ADDomain).DistinguishedName      # e.g. DC=corp,DC=khlab,DC=internal
$Root       = "KHLAB"
$Depts      = "IT","HR","Finance","Sales","Operations"
$UsersPerDept = 11
$DefaultPw  = Read-Host "Initial password for all lab users" -AsSecureString
$ErrorActionPreference = "Stop"   # fail fast: never leave half-created (disabled) accounts behind

# Pre-flight: prove the password meets domain policy before touching anything
$probe = "pwprobe$(Get-Random -Maximum 9999)"
try {
    New-ADUser -Name $probe -SamAccountName $probe -AccountPassword $DefaultPw -Enabled $true
    Remove-ADUser -Identity $probe -Confirm:$false
} catch {
    if (Get-ADUser -Filter "SamAccountName -eq '$probe'") { Remove-ADUser -Identity $probe -Confirm:$false }
    throw "Password rejected by domain policy (needs 3 of: upper, lower, number, symbol). Nothing was created."
}

$First = "James","Maria","David","Aisha","Kevin","Sofia","Marcus","Priya","Andre","Emily",
         "Jordan","Nadia","Chris","Leah","Omar","Grace","Tyler","Zara","Ethan","Ruth",
         "Malik","Hannah","Diego","Chloe","Isaiah","Mia","Noah","Layla","Caleb","Ivy"
$Last  = "Pierre","Johnson","Garcia","Nguyen","Brown","Patel","Davis","Joseph","Miller","Wilson",
         "Lopez","Taylor","Thomas","Moore","Jackson","Martin","Lee","Clark","Lewis","Walker"

function New-OUIfMissing($Name, $Path) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "OU  created: $Name"
    }
}

# --- OU tree ------------------------------------------------------------------
New-OUIfMissing $Root $DomainDN
$RootDN = "OU=$Root,$DomainDN"
"Users","Groups","Computers","Service Accounts","Disabled" | ForEach-Object { New-OUIfMissing $_ $RootDN }
"Workstations","Servers" | ForEach-Object { New-OUIfMissing $_ "OU=Computers,$RootDN" }
$Depts | ForEach-Object { New-OUIfMissing $_ "OU=Users,$RootDN" }

# --- Groups + users -----------------------------------------------------------
$rand = New-Object System.Random 42   # fixed seed = same names every rebuild
foreach ($d in $Depts) {
    $grp = "GG_$d"
    if (-not (Get-ADGroup -Filter "Name -eq '$grp'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $grp -GroupScope Global -GroupCategory Security -Path "OU=Groups,$RootDN" -Description "$d department"
        Write-Host "Grp created: $grp"
    }
    $ouDN = "OU=$d,OU=Users,$RootDN"
    $have = (Get-ADUser -Filter * -SearchBase $ouDN).Count
    while ($have -lt $UsersPerDept) {
        $fn  = $First[$rand.Next($First.Count)]
        $ln  = $Last[$rand.Next($Last.Count)]
        $num = $rand.Next(10,99)
        $sam = ("{0}.{1}{2}" -f $fn, $ln, $num).ToLower()
        $cn  = "$fn $ln $num"                      # unique display name avoids CN collisions
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) { continue }
        New-ADUser -Name $cn -DisplayName "$fn $ln" -GivenName $fn -Surname $ln -SamAccountName $sam `
            -UserPrincipalName "$sam@$((Get-ADDomain).DNSRoot)" -Department $d -Title "$d Staff" `
            -Path $ouDN -AccountPassword $DefaultPw -Enabled $true -ChangePasswordAtLogon $true
        Add-ADGroupMember -Identity $grp -Members $sam
        $have++
    }
}

# --- Summary (counts ENABLED accounts, not just objects) -----------------------
$Depts | ForEach-Object {
    $all = Get-ADUser -Filter * -SearchBase "OU=$_,OU=Users,$RootDN"
    "{0,-11} {1} users ({2} enabled)" -f $_, $all.Count, ($all | Where-Object Enabled).Count
}
