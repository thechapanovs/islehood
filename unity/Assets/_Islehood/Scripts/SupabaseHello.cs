using System;
using UnityEngine;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

// Describes one row of the heartbeat table (like a Python dataclass).
[Table("heartbeat")]
public class Heartbeat : BaseModel
{
    [PrimaryKey("id")] public long Id { get; set; }
    [Column("ran_at")] public DateTime RanAt { get; set; }
}

// MonoBehaviour = a script you can attach to an object in a Unity scene.
public class SupabaseHello : MonoBehaviour
{
    private string message = "Connecting to Supabase...";

    // Start runs once when the scene begins. "async" lets us await network calls
    // (same idea as async/await in Python).
    private async void Start()
    {
        try
        {
            var options = new Supabase.SupabaseOptions { AutoConnectRealtime = false };
            var client = new Supabase.Client(SupabaseConfig.Url, SupabaseConfig.PublishableKey, options);
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
                message = $"Last heartbeat:\n{latest.RanAt.ToLocalTime():MMM d, h:mm:ss tt}";
            }
        }
        catch (Exception e)
        {
            message = "Error: " + e.Message;
            Debug.LogException(e);
        }

        Debug.Log(message);
    }

    // OnGUI draws simple on-screen boxes. Fine for a throwaway test screen.
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
