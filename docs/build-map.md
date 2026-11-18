Islehood Build Map (Tech Setup chat)
How every piece of the stack connects, and where each v1 feature starts and finishes. Written Nov 16, 2026, updated Nov 17 with the Render setup (Step 0B, done) and the Unity foundation steps (Step 0C, Build: Phone App chat). Full stack list: "Tech stack" in claude/home-base.md.

Part 1: How the pieces connect
The one rule
* Everything talks to Supabase. Nothing talks to each other directly.
* The phone app, the web app, the invite page, and the Python job all read and write the same Supabase database
* This keeps things simple: if you know what's in the database, you know what every piece sees
Each connection
From	To	How	What flows
iPhone app (Unity)	Supabase Auth	C# Supabase library	Sign up, log in, magic link, Google, Apple
iPhone app (Unity)	Supabase Database	C# Supabase library	Islands, avatars, Pals, prompts, answers, stars, votes
iPhone app (Unity)	Supabase Storage	C# Supabase library	Photo answers (shrunk before upload)
iPhone app (Unity)	Supabase Realtime	C# Supabase library	Live "4 of 5 answered" counter, new build alerts
iPhone app (Unity)	The phone itself	Unity Mobile Notifications	Local alerts at 12 PM ("prompt is here") and reveal time ("sky is ready"), scheduled from times stored in Supabase
Web app (Unity Web build)	Supabase	Same C# library as the phone	Same as the phone. Notifications become an in-page banner
Invite preview page (plain web page)	Supabase	supabase-js (small JavaScript library)	Read-only island preview: name, avatars, Pals, builds. Nothing private
Python job (Render Cron Job)	Supabase Database	Python Supabase library with the secret key	Picks each island's daily prompt, runs each island's reveal, fills the build pool, opens and closes votes
Render's scheduler	Python job	Starts the job every minute	"Which islands need a prompt or a reveal right now?"
Blender	Unity project	Export .fbx, drop into Assets	Island, builds, Pals, avatar parts
Unity project	Xcode → TestFlight	Unity iOS build	Beta builds for iPhone testers
Unity project	Web host (Cloudflare Pages or Firebase Hosting)	Unity Web build	The browser version
Everything	GitHub (thechapanovs/islehood)	Git + Git LFS	All code and art in one repo
iPhone and web app	Unity Cloud Diagnostics	Built into Unity	Crash reports
iPhone and web app	Supabase events table	C# library	Beta numbers: sign-ups, answers, sky opens, votes
Who is allowed to see what (security)
* Row level security rules in Supabase decide what each person can read and write
* The app only ever uses the publishable (public) key. It can only do what the rules allow
* The Python job uses the secret key, which skips the rules. That key lives only in Render's environment settings, never in the app or the repo
* The most important rule: answers are hidden from other members until the island's reveal
Repo layout (one GitHub repo: thechapanovs/islehood)

islehood/
  unity/          the Unity project (phone + web)
  backend/        the Python job + pytest tests (runs on Render)
  web-preview/    the plain invite preview page
  supabase/       table setup (SQL) and security rules
  art/            exported .fbx files (big files go through Git LFS)

Part 2: Where to start and finish
The pattern for every feature
1. Data first: tables and security rules in Supabase
2. Logic next: Python job code, if the feature needs it (with pytest tests)
3. Art: Blender models, if the feature needs them (3D Art chat)
4. Screens: Unity scenes and UI
5. Connect: the Unity screens read and write Supabase
6. Test on the iPhone 13, then in a browser
7. Done when: the feature's finish line below is true
Step 0: Foundation (before any feature)
* Start: create the Supabase project and the GitHub repo (layout above) ✅
* Set up the Python job on Render (every command is in Step 0B below) ✅ done Nov 17
* Create the real Unity project (islehood, version 6000.3.28f1) inside unity/ (every command is in Step 0C below)
* Add the C# Supabase library and prove Unity can read one row (Step 0C)
* Finish: the latest heartbeat row from Supabase shows up in the Unity app on the iPhone, and the Render job writes a heartbeat row every minute

Step 0B: Render setup (every command) ✅ done Nov 17
What we're building: a tiny Python script that Render runs every minute. For now it only writes a "heartbeat" row to Supabase, which proves the whole chain works. Later, the same job picks prompts and runs reveals.
Why a Render Cron Job, every minute (decided Nov 17, see Home Base):
* Nothing calls the Python code directly (everything talks to Supabase), so it's a plain script that starts, does its work, and exits. No FastAPI needed
* Render bills cron jobs only while they run, with a $1/month minimum per cron job
* Render never runs two copies of the same job at once, so a slow reveal can't overlap the next run and hand out stars twice
* Every minute (not every 5) keeps reveals from landing late
* Check render.com/pricing for any workspace fee before signing up
You need first:
* The Supabase project created (any name, for example islehood)
* The GitHub repo thechapanovs/islehood
* Python 3 on your Mac
B1. Make the heartbeat table in Supabase
1. Supabase dashboard → your project → SQL Editor → New query
2. Paste and click Run:

sql
create table if not exists public.heartbeats (
  id bigint generated always as identity primary key,
  source text not null,
  ran_at timestamptz not null default now()
);

alter table public.heartbeats enable row level security;
* Turning on row level security with no rules means the app can't touch this table. Only the secret key (the Render job) can write to it
3. Save the same SQL in the repo as supabase/001_heartbeats.sql (B3 makes the folder)
B2. Get the two values Render needs
1. Supabase dashboard → Project Settings → Data API (or API): copy the Project URL
2. Project Settings → API Keys: copy the secret key (starts with sb_secret_). If your project only shows older keys, use the service_role key instead
3. Never paste the secret key into a file in the repo, a chat with your teammate, or the Unity project
B3. Create the backend folder on your Mac
Open Terminal and run each line:

bash
cd ~/Projects
git clone https://github.com/thechapanovs/islehood.git
cd islehood
mkdir -p backend/jobs backend/tests supabase
cd backend
python3 --version
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install supabase pytest
pip freeze > requirements.txt
touch jobs/__init__.py tests/__init__.py
* If git clone says the folder already exists, skip that line and just run cd ~/Projects/islehood
* Write down the version python3 --version prints (for example 3.12.8). Render needs it in B6
B4. Add the job code
Create backend/jobs/tick.py:

python
import os
from datetime import datetime, timezone

from supabase import create_client


def build_heartbeat(now: datetime) -> dict:
    return {"source": "render-cron", "ran_at": now.isoformat()}


def main() -> None:
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    row = build_heartbeat(datetime.now(timezone.utc))
    client.table("heartbeats").insert(row).execute()
    print(f"tick ok {row['ran_at']}")


if __name__ == "__main__":
    main()
Create backend/tests/test_tick.py:

python
from datetime import datetime, timezone

from jobs.tick import build_heartbeat


def test_build_heartbeat():
    now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
    row = build_heartbeat(now)
    assert row["source"] == "render-cron"
    assert row["ran_at"] == "2026-11-17T12:00:00+00:00"
Create backend/.gitignore:

.venv/
__pycache__/
.env
.pytest_cache/
B5. Test it on your Mac
Still in backend/ with the virtual environment on (source .venv/bin/activate):

bash
python -m pytest
export SUPABASE_URL="paste-your-project-url"
export SUPABASE_SECRET_KEY="paste-your-secret-key"
python -m jobs.tick
* pytest should say 1 passed
* python -m jobs.tick should print tick ok ...
* Check Supabase → Table Editor → heartbeats: one new row
Then push it:

bash
cd ~/Projects/islehood
git checkout -b backend-heartbeat
git add backend supabase
git status
git commit -m "Add heartbeat job for Render"
git push -u origin backend-heartbeat
* git status should not list .venv or any file with your key in it. If it does, stop and fix .gitignore first
* Open a pull request on GitHub, have your teammate review, then merge into main (your "no pushing straight to main" rule)
B6. Create the Render Cron Job
1. Go to render.com → sign up with GitHub
2. When asked for repo access, give Render access to thechapanovs/islehood only (you may need to be an owner of the thechapanovs org, or ask the owner to approve)
3. Add a payment method (cron jobs are paid, with a $1/month minimum)
4. New → Cron Job → pick thechapanovs/islehood
5. Fill in:
Setting	Value
Name	islehood-tick
Branch	main
Root Directory	backend
Runtime / Language	Python 3
Build Command	pip install -r requirements.txt
Command	python -m jobs.tick
Schedule	* * * * * (every minute; Render's times are in UTC)
Instance type	The smallest one
	6	Environment Variables:
Key	Value
SUPABASE_URL	your Project URL
SUPABASE_SECRET_KEY	your secret key
PYTHON_VERSION	the version from B3, for example 3.12.8
	7	Click Create Cron Job
B7. Check it works
1. On the cron job's page, click Trigger Run (runs it now instead of waiting)
2. Open Logs: you should see tick ok ...
3. Supabase → Table Editor → heartbeats: a row with source render-cron
4. Wait 3 minutes: about three more rows should appear on their own
5. Later, once the real prompt and reveal code is in the job, remove the heartbeat insert. Every minute adds up to about 43,000 rows a month
Done when: a new heartbeat row shows up every minute without you doing anything.
B8. Troubleshooting
Problem	Fix
zsh: command not found: python3	Install Apple's developer tools: xcode-select --install, then run python3 --version again
ModuleNotFoundError: No module named 'supabase' on your Mac	Turn the environment back on: cd ~/Projects/islehood/backend then source .venv/bin/activate then pip install -r requirements.txt
ModuleNotFoundError: No module named 'jobs'	You're in the wrong folder. Run cd ~/Projects/islehood/backend and try again
KeyError: 'SUPABASE_URL' on your Mac	Run the two export lines from B5 again (they reset when you close Terminal)
KeyError: 'SUPABASE_URL' on Render	The environment variables are missing or misspelled. Check B6 step 6 (names are case-sensitive)
Render build fails on a Python version error	Set PYTHON_VERSION to a full version like 3.12.8, then Manual Deploy → Deploy latest commit
Render can't find requirements.txt	Root Directory must be exactly backend
Supabase error about permission or 401	You used the publishable key. Use the secret key (or service_role)
Supabase error that heartbeats doesn't exist	Run the B1 SQL again in the SQL Editor
Render can't see the repo	Render dashboard → Account Settings → GitHub → configure access, and add thechapanovs/islehood. An org owner may need to approve
Secret key got pushed to GitHub by mistake	Supabase → API Keys → create a new secret key and delete the old one, then update Render's SUPABASE_SECRET_KEY
Step 0C: The real Unity project + first Supabase read (every command, Build: Phone App chat)
What we're building: the real islehood Unity project inside unity/, with the Supabase C# library added. A test screen reads the latest heartbeat row (written every minute by the Render job) and shows its time. When that time shows up on the iPhone, every link in the chain works: Render → Supabase → Unity → iPhone.
You need first:
* Step 0B done (heartbeat rows appearing every minute) ✅
* Unity Hub with Unity 6000.3.28f1 installed, including iOS Build Support
* Your iPhone 13 and its cable
* Your Supabase Project URL and publishable key (not the secret key)
C1. Let the app read heartbeats (test only)
Right now heartbeats has row level security on with no rules, so the app's publishable key can't read it. Add one read-only rule.
1. Supabase dashboard → SQL Editor → New query
2. Paste and click Run:

sql
grant select on public.heartbeats to anon, authenticated;

create policy "Test only: anyone can read heartbeats"
on public.heartbeats
for select
to anon, authenticated
using (true);
* The app can now read heartbeats, but still can't add, change, or delete them
* This rule is for testing only. Delete it when the heartbeat job is removed (see C13)
3. Save the same SQL in the repo as supabase/002_heartbeats_read_test.sql (you'll commit it in C10)
C2. Get the publishable key
1. Supabase dashboard → Project Settings → API Keys
2. Copy the publishable key (starts with sb_publishable_). If your project only shows older keys, use the anon key
3. This key is meant to be inside the app, so it's fine in the Unity project. The secret key never goes in Unity
C3. Update your copy of the repo
In Terminal:

bash
cd ~/Projects/islehood
git checkout main
git pull
git checkout -b unity-foundation
ls
* ls should show backend and supabase. There should be no unity folder yet. If there is one, stop and check what's in it before going on
C4. Create the Unity project inside unity/
1. Open Unity Hub → Projects → New project
2. At the top, set Editor Version to 6000.3.28f1
3. Pick the template Universal 3D (download it if Hub asks)
4. Project name: unity
5. Location: click the folder icon and pick ~/Projects/islehood (your home folder → Projects → islehood)
6. Turn off "Connect to Unity Cloud" and "Use Unity Version Control" (you use GitHub instead)
7. Click Create project and wait for Unity to open (the first time takes a few minutes)
* The project is named unity only so the folder matches the repo layout. The app's real name gets set to Islehood in C6
Check in Terminal:

bash
ls ~/Projects/islehood/unity
* You should see Assets, Packages, ProjectSettings, and Library (among others)
C5. Git setup for Unity (skip any part the Tech Setup chat already did)
5a. The Unity .gitignore (keeps Unity's huge cache folders out of GitHub). In Terminal:

bash
cd ~/Projects/islehood
curl -o unity/.gitignore https://raw.githubusercontent.com/github/gitignore/main/Unity.gitignore
echo "" >> unity/.gitignore
echo "# Islehood: local build output" >> unity/.gitignore
echo "/[Bb]uilds/" >> unity/.gitignore
head -20 unity/.gitignore
* The file must sit inside unity/ (not the repo's top folder), because its rules are written relative to the Unity project folder
5b. Git LFS (for big art files). Check first:

bash
git lfs version
* If that prints a version, skip to 5c
* If it says command not found, install it:

bash
brew install git-lfs
git lfs install
* If brew says command not found, see the C12 troubleshooting table
5c. Track big files with LFS. From ~/Projects/islehood:

bash
git lfs track "*.fbx" "*.glb" "*.blend" "*.png" "*.jpg" "*.psd" "*.tga" "*.wav" "*.mp3" "*.ogg" "*.ttf" "*.otf"
cat .gitattributes
5d. Unity Smart Merge (lets Git merge scene and prefab changes from both of you). From ~/Projects/islehood:

bash
printf '\n# Unity Smart Merge\n*.unity merge=unityyamlmerge eol=lf\n*.prefab merge=unityyamlmerge eol=lf\n*.asset merge=unityyamlmerge eol=lf\n' >> .gitattributes
git config merge.unityyamlmerge.name "Unity SmartMerge"
git config merge.unityyamlmerge.driver '"/Applications/Unity/Hub/Editor/6000.3.28f1/Unity.app/Contents/Tools/UnityYAMLMerge" merge -p %O %B %A %A'
git config merge.unityyamlmerge.recursive binary
ls "/Applications/Unity/Hub/Editor/6000.3.28f1/Unity.app/Contents/Tools/UnityYAMLMerge"
* The last line should print the path back. If it says "No such file," see C12
* The three git config lines only apply to your Mac. Your teammate runs the same three lines after cloning
C6. Project settings
In Unity:
    * Edit → Project Settings → Editor
    * Asset Serialization → Mode: Force Text
    * Version Control → Mode: Visible Meta Files
    * (Unity 6 usually has both set already. Just check)
    * Edit → Project Settings → Player → top of the page:
    * Company Name: thechapanovs
    * Product Name: Islehood
    * Still in Player, click the iPhone/iOS tab (the phone icon) → Other Settings:
    * Bundle Identifier: com.thechapanovs.islehood
    * Managed Stripping Level: Minimal (so the iPhone build doesn't strip code the Supabase library needs)
    * Target minimum iOS Version: leave the default
1. File → Save Project
C7. VS Code for Unity (skip if the Tech Setup chat already did this)
In Terminal:

bash
brew install --cask visual-studio-code
brew install --cask dotnet-sdk
code --version
code --install-extension visualstudiotoolsforunity.vstuc
code --install-extension ms-dotnettools.csdevkit
* If code says command not found: open VS Code → press Cmd+Shift+P → type Shell Command: Install 'code' command in PATH → Enter, then run the code lines again
In Unity:
1. Window → Package Manager → In Project: check that Visual Studio Editor is listed. If not: + → Install package by name → com.unity.ide.visualstudio → Install
2. Unity → Settings → External Tools → External Script Editor: pick Visual Studio Code
3. Click Regenerate project files
C8. Install the Supabase C# library
8a. Newtonsoft JSON (Unity's own version)
1. Window → Package Manager → + (top left) → Install package by name
2. Name: com.unity.nuget.newtonsoft-json → Install
* If it says it's already installed, that's fine
8b. NuGetForUnity (lets Unity install packages from NuGet, where the Supabase library lives)
1. Package Manager → + → Install package from git URL
2. Paste: https://github.com/GlitchEnzo/NuGetForUnity.git?path=/src/NuGetForUnity → Install
3. A new NuGet menu appears in Unity's top menu bar
8c. The Supabase library
1. NuGet → Manage NuGet Packages
2. Online tab → search Supabase
3. Pick the package named exactly Supabase (by the supabase-community; not supabase-csharp, which is the old name) → Install
4. Wait for it to finish, then check the Console (Window → General → Console)
* No red errors: go on to 8d
* Red errors about Newtonsoft.Json or "multiple precompiled assemblies": see C12
8d. Keep the library safe on iPhone builds. Create the file unity/Assets/link.xml:

bash
cd ~/Projects/islehood/unity/Assets
cat > link.xml << 'EOF'
<linker>
  <assembly fullname="Supabase" preserve="all"/>
  <assembly fullname="Supabase.Core" preserve="all"/>
  <assembly fullname="Supabase.Postgrest" preserve="all"/>
  <assembly fullname="Supabase.Gotrue" preserve="all"/>
  <assembly fullname="Supabase.Realtime" preserve="all"/>
  <assembly fullname="Supabase.Storage" preserve="all"/>
  <assembly fullname="Supabase.Functions" preserve="all"/>
</linker>
EOF
cat link.xml
C9. The test screen
9a. Make the folders and the script file. In Terminal:

bash
mkdir -p ~/Projects/islehood/unity/Assets/Scripts/Dev
mkdir -p ~/Projects/islehood/unity/Assets/Scenes
code ~/Projects/islehood/unity/Assets/Scripts/Dev/SupabaseHello.cs
9b. Paste this into SupabaseHello.cs and save:

csharp
using System;
using UnityEngine;
using Supabase;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

[Table("heartbeats")]
public class Heartbeat : BaseModel
{
    [PrimaryKey("id", false)]
    public long Id { get; set; }

    [Column("source")]
    public string Source { get; set; }

    [Column("ran_at")]
    public DateTime RanAt { get; set; }
}

public class SupabaseHello : MonoBehaviour
{
    [SerializeField] private string supabaseUrl = "";
    [SerializeField] private string publishableKey = "";

    private string message = "Connecting to Supabase...";

    private async void Start()
    {
        try
        {
            var options = new SupabaseOptions { AutoConnectRealtime = false };
            var client = new Client(supabaseUrl, publishableKey, options);
            await client.InitializeAsync();

            var response = await client
                .From<Heartbeat>()
                .Order("ran_at", Supabase.Postgrest.Constants.Ordering.Descending)
                .Limit(1)
                .Get();

            if (response.Models.Count == 0)
            {
                message = "Connected, but no heartbeat rows yet.";
            }
            else
            {
                var latest = response.Models[0];
                message = $"Last heartbeat:\n{latest.RanAt.ToLocalTime():MMM d, h:mm:ss tt}\nfrom {latest.Source}";
            }
        }
        catch (Exception e)
        {
            message = "Error: " + e.Message;
            Debug.LogException(e);
        }

        Debug.Log(message);
    }

    private void OnGUI()
    {
        var box = new Rect(40, 120, Screen.width - 80, Screen.height / 3f);
        GUI.Box(box, "");

        var style = new GUIStyle(GUI.skin.label)
        {
            fontSize = Mathf.RoundToInt(Screen.height / 30f),
            wordWrap = true,
            alignment = TextAnchor.MiddleCenter
        };
        style.normal.textColor = Color.white;

        GUI.Label(box, message, style);
    }
}
* This is a throwaway test screen. Real screens come with Feature 1
9c. Make the test scene. In Unity:
1. File → New Scene → Basic (URP) → Create
2. File → Save As → Assets/Scenes/ → name it SupabaseHello → Save
3. GameObject → Create Empty. In the Inspector, rename it SupabaseHello
4. Add Component → search SupabaseHello → click it
    * In the component, paste:
    * Supabase Url: your Project URL (from Step 0B, B2)
    * Publishable Key: the key from C2
5. File → Save
6. File → Build Profiles (or Build Settings) → Scene List → Add Open Scenes. Uncheck any other scene so Scenes/SupabaseHello is the only one checked
C10. Test in Play mode on your Mac
1. Press Play (the ▶ button at the top)
2. Within a few seconds the box should say Last heartbeat: with a time from the last minute or so
3. Press Play again to stop, wait one minute, and press Play again. The time should move forward
* If the box says Error:, check the C12 table
Then commit and push:

bash
cd ~/Projects/islehood
git add .gitattributes unity supabase
git status
git commit -m "Add Unity project with Supabase test screen"
git push -u origin unity-foundation
* git status should not list unity/Library/, unity/Temp/, unity/Logs/, or unity/Builds/. If it does, the .gitignore from 5a is in the wrong place. Stop and check C12
* git status must not show any file with your secret key. The publishable key inside the scene file is fine
* Open a pull request on GitHub, have your teammate review, then merge into main
C11. Build it to your iPhone
11a. Xcode (skip if already installed and opened once)
1. Install Xcode from the Mac App Store (it's large, so give it time)
2. Then in Terminal:

bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -version
3. Open Xcode once → Xcode → Settings → Accounts → + → Apple ID → sign in. This makes a free Personal Team (no $99 account needed for testing on your own phone)
11b. Turn on Developer Mode on the iPhone
1. Plug the iPhone into the Mac with the cable. Tap Trust on the phone if asked
2. iPhone: Settings → Privacy & Security → Developer Mode → on → restart when asked → tap Turn On after it restarts
* If Developer Mode isn't in the list, it shows up after step 11d's first run attempt. Come back to this step then
11c. Make the Xcode project from Unity
1. Unity: File → Build Profiles → iOS → Switch Platform (wait for it)
2. Click Build → make a new folder ~/Projects/islehood/unity/Builds/iOS → Choose
3. When it finishes, Finder opens that folder
11d. Run it from Xcode
1. Double-click Unity-iPhone.xcodeproj in Builds/iOS
2. In Xcode's left sidebar, click Unity-iPhone (the blue icon) → target Unity-iPhone → Signing & Capabilities
3. Check Automatically manage signing, then set Team to your Personal Team
4. If it says the bundle identifier is taken, change it to com.thechapanovs.islehood.dev
5. At the top of Xcode, pick your iPhone as the run destination
6. Press Run (the ▶ button)
7. The first time, the phone may say "Untrusted Developer." On the iPhone: Settings → General → VPN & Device Management → your Apple ID → Trust. Then press Run in Xcode again
8. The app opens on the phone and shows Last heartbeat: with a recent time
* Apps from a free Personal Team stop opening after 7 days. Just press Run in Xcode again to reinstall. This goes away once you have the paid Apple Developer account
Done when (Step 0 finish line): the iPhone shows a heartbeat time from the last minute or two, and closing and reopening the app a minute later shows a newer time.
C12. Troubleshooting
Problem	Fix
zsh: command not found: brew	Install Homebrew: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)", then run the two echo/eval lines it prints at the end, then close and reopen Terminal
Unity Hub doesn't list 6000.3.28f1 when creating the project	Hub → Installs → check it's there. If not: Install Editor → Archive tab → find 6000.3.28f1
No iOS option in Build Profiles, or it says the module isn't installed	Hub → Installs → gear next to 6000.3.28f1 → Add modules → check iOS Build Support → Install, then restart Unity
ls .../UnityYAMLMerge says "No such file"	Your Unity is installed somewhere else. Run find /Applications -name UnityYAMLMerge 2>/dev/null and use that path in the git config merge.unityyamlmerge.driver line
git status lists unity/Library/ or thousands of files	The .gitignore isn't inside unity/. Run ls -a ~/Projects/islehood/unity and make sure .gitignore is there. If you already ran git add, undo it with git reset, fix the file, then add again
NuGet menu doesn't appear after 8b	Check the Console for red errors, then Assets → Refresh. If still missing, quit and reopen Unity
Search for Supabase in NuGet finds nothing	NuGet → Preferences: make sure the nuget.org source is checked, then search again
Console: "Multiple precompiled assemblies with the same name Newtonsoft.Json.dll"	NuGet added a second copy. In Terminal: ls ~/Projects/islehood/unity/Assets/Packages, then delete the Newtonsoft one: rm -rf ~/Projects/islehood/unity/Assets/Packages/Newtonsoft.Json.* (also delete its .meta file if one is left), then go back to Unity and wait for it to recompile
Console: The type or namespace name 'Supabase' could not be found	8c didn't finish. NuGet → Manage NuGet Packages → Installed tab: check Supabase is there. If not, install it again
Console: 'Client' is an ambiguous reference	Change new Client( to new Supabase.Client( in SupabaseHello.cs
VS Code shows red squiggles everywhere but Unity has no errors	In Unity: Settings → External Tools → Regenerate project files, then close and reopen VS Code
The box says Error: ... 401 or "Invalid API key"	Wrong key in the Inspector. Use the publishable key (C2), not the secret key, and check there are no spaces at the start or end
The box says Error: ... permission denied for table heartbeats	Run the C1 SQL again (the grant line is the one that fixes this)
The box says Connected, but no heartbeat rows yet	The C1 policy is missing (the app sees zero rows it's allowed to read), or the Render job stopped. Check Supabase → Table Editor → heartbeats for recent rows, then rerun C1
The box says Error: ... could not resolve host or a network error	Check the Project URL in the Inspector (should look like https://xxxx.supabase.co, no trailing slash) and that the Mac or phone is online
The time shown is 6 hours off	It's showing UTC. Make sure the script has .ToLocalTime() and that the iPhone's time zone is set correctly
Box stays on "Connecting to Supabase..." forever	Open the Console (or Xcode's bottom panel on the iPhone) for the real error and match it to a row above
Works in Play mode but crashes or errors only on the iPhone	Check C6 (Managed Stripping Level: Minimal) and that Assets/link.xml exists (8d). Then build again from C11c
Xcode: "Signing for Unity-iPhone requires a development team"	11d step 3: pick your Personal Team. If none is listed, do 11a step 3 first
Xcode: "Failed to register bundle identifier"	Change the bundle identifier to com.thechapanovs.islehood.dev (11d step 4)
Xcode: "Developer Mode disabled"	Do 11b, then press Run again
Phone: "Untrusted Developer"	iPhone Settings → General → VPN & Device Management → your Apple ID → Trust
The app worked last week but now won't open	Free Personal Team apps expire after 7 days. Plug in and press Run in Xcode again
Xcode: "No profiles found" / "Your team has no devices"	Xcode only registers the phone when it is the run destination. Plug in and unlock the phone, Shift+Command+2 (Devices and Simulators) → click the iPhone → tick Show as run destination. Pick the iPhone in the destination menu at the top of Xcode (not Any iOS Device), then uncheck and re-check Automatically manage signing
Unity-iPhone.xcodeproj is not in Builds/iOS	If you chose the Builds folder itself in C11c, the Xcode project is in unity/Builds/. That works fine and is still ignored by Git
Step 0C as built in the repo	This repo's table is heartbeat (singular, only a ran_at column), the C# test screen is unity/Assets/_Islehood/Scripts/SupabaseHello.cs, the scene is _Islehood/Scenes/SupabaseHello, the read rule is supabase/002_heartbeat_read_test.sql, and the key lives in SupabaseConfig.cs. Use these in place of heartbeats, Scripts/Dev and 002_heartbeats_read_test.sql
C13. Clean up later (when real features replace the test)
* Delete the test read rule in Supabase SQL Editor:

sql
drop policy if exists "Test only: anyone can read heartbeats" on public.heartbeats;
revoke select on public.heartbeats from anon, authenticated;
* Delete Assets/Scripts/Dev/SupabaseHello.cs and Assets/Scenes/SupabaseHello.unity
* Remove the heartbeat insert from the Render job (see B7 step 5)

Feature 1: Accounts and islands
Start: tables users, islands, memberships + security rules
1. Turn on Supabase Auth: email and password, magic link, Google (Apple waits for the Apple Developer account)
2. Database trigger: a new user automatically gets their own solo island
3. Unity screens: welcome, sign up (display name, 13+ check, terms line, time zone detected)
4. Invite codes: each island gets one, plus a share link
5. Invite preview page (web-preview/): opens from the link, shows the island, loads in under 5 seconds
6. Deep link: tapping the link opens the app if installed, otherwise the preview page
7. Join flow: new user signs up and joins; existing user logs in and their solo island is set aside (never deleted)
8. Leave island: returns to the old solo island
Finish: a new user signs up on the iPhone and lands on their own island. A friend taps the invite link, sees the preview in under 5 seconds, joins, and both see the same island.

Feature 2: Avatar creator and Pocket Pal
Start: avatar columns on users (skin tone, hair style, hair color, eyes, outfit) and a pals table + security rules
1. Art (3D Art chat): base avatar, hair styles (including curly, coily, braids, locs), outfits, eyes, and 4 Pals with 3 moods each
2. Unity creator screen: swap parts live, pick a Pal
3. Save choices to Supabase
4. Show every member's avatar and Pal on the island
Finish: after sign-up you make your avatar and pick a Pal, and your friends see them on the shared island.

Feature 3: Daily prompt
Start: tables prompts, daily_prompts, answers + security rules (answers hidden from others until the reveal)
1. Write the first 40 prompts into the prompt bank (aim for 100 before the beta)
2. Python job (in backend/jobs/, run by the Render cron every minute): picks each island's prompt (random, never repeated, same answer type never more than 2 days in a row). Test with pytest
3. Prompt timing: local noon for each person, never before the island's previous reveal. Test with time zones far ahead and far behind
4. Unity prompt card: tap choice, one line, photo
5. Photo answers: shrink, then upload to Supabase Storage
6. Edit before the reveal ("Updated" note), skip anytime
7. The private "your star is waiting" moment (dim star settles, Pal reacts)
8. Live counter with Supabase Realtime ("4 of 5 answered," never who)
9. Local notification at 12 PM
Finish: the prompt shows up at noon, you answer with a tap, a line, or a photo, your friends' counters tick up instantly, and nobody else can see your answer.

Feature 4: Night Sky reveal
Start: stars table + a security rule that opens answers to members after the reveal
1. Python reveal job (run by the Render cron every minute): at each island's reveal time, one star per answer, sky scales to active members, stars added to the build pool. Test with pytest (this is the piece most likely to break quietly)
2. Unity time of day: sunny, golden hour, night, following the island's schedule
3. Reveal scene: friends who answered gather in a circle, each star rises from its friend's avatar, friends who didn't answer sit nearby
4. Tap a star to see that friend's answer
5. Late answer moment: the avatar walks over and their star rises
6. Sky history: browse past nights
7. Local notification: "The sky is ready"
Finish: at reveal time every member sees the same sky at the same moment, each star rises from the right avatar, and tapping a star shows the answer.

Feature 5: Island building
Start: tables builds and votes + security rules
1. Python job: pool size (active members × 2 first, then × 4), open the vote when the pool fills, close it at the next reveal or when everyone has voted, coin-flip ties, losers sit out one vote. Test with pytest
2. Art (3D Art chat): the 10 builds
3. Unity vote screen (3 choices)
4. Daytime progress: "12 stars until the next build"
5. The winning build appears on the island during the next reveal
Finish: the pool fills, the group votes, and the winning build appears on everyone's island at the next reveal.

Feature 6: Safety, polish, and store requirements
Start: reports table + security rules
1. Report an answer, and the island creator can remove a member
2. Delete your own answers, and delete your account from inside the app
3. Privacy policy page on a public web address
4. Bonus star buttons (Study, Move, Chore, Self-care), capped at 3 a day
5. Events table for beta numbers, and Unity Cloud Diagnostics for crashes
6. Sign in with Apple (once the Apple Developer account is paid)
Finish: everything the App Store requires is in, and you can see crashes and beta numbers.

Feature 7: Web version
Start: a Unity Web build of the working app
1. Phone layout centered in a column, sky filling the background
2. In-page banner instead of notifications
3. Photo answers by file upload or webcam
4. Loading sky while the world downloads
5. Host it (Cloudflare Pages or Firebase Hosting) and connect the invite links
Finish: the full loop (sign up, answer, reveal, build) works in Chrome and Safari on a laptop and in a phone browser.

After all 7: the beta
* Pay for the Apple Developer account (if not already), set up TestFlight, invite 3 to 5 groups
* Done when (from the roadmap): half of testers still open the app in week 3
Order and ownership
* Build in the order above: each feature depends on the ones before it
* The team splits by feature, so once Step 0 and Feature 1 are done, the two of you can work on different features at the same time (for example, one on Feature 2 while the other starts Feature 3)
* Who owns which feature: still to assign (Home Base open question)
