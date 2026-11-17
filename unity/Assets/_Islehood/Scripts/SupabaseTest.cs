using UnityEngine;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

// Describes one row of the hello table
[Table("hello")]
public class HelloRow : BaseModel
{
    [PrimaryKey("id")] public long Id { get; set; }
    [Column("message")] public string Message { get; set; }
}

public class SupabaseTest : MonoBehaviour
{
    async void Start()
    {
        var options = new Supabase.SupabaseOptions { AutoConnectRealtime = false };
        var client = new Supabase.Client(SupabaseConfig.Url, SupabaseConfig.PublishableKey, options);
        await client.InitializeAsync();

        var result = await client.From<HelloRow>().Get();
        foreach (var row in result.Models)
        {
            Debug.Log("From Supabase: " + row.Message);
        }
    }
}