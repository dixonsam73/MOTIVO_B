import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response("Missing Authorization header", { status: 401 });
  }

  const token = authHeader.replace("Bearer ", "");

  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: userData, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !userData?.user?.id) {
    return new Response("Invalid session", { status: 401 });
  }

  const uid = userData.user.id;

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  try {
    // 1️⃣ Delete avatar first
    const { data: acct } = await admin
      .from("account_directory")
      .select("avatar_key")
      .eq("user_id", uid)
      .maybeSingle();

    if (acct?.avatar_key) {
      await admin.storage.from("avatars").remove([acct.avatar_key]);
    }

    // 2️⃣ Recursively delete attachments
    const bucket = "attachments";
    const prefix = `users/${uid}`;

    async function deleteFolder(folder: string) {
      const { data: items } = await admin.storage
        .from(bucket)
        .list(folder, { limit: 1000 });

      if (!items) return;

      const files: string[] = [];
      const subfolders: string[] = [];

      for (const item of items) {
        const isFolder = (item as any).metadata == null;
        const fullPath = `${folder}/${item.name}`;

        if (isFolder) subfolders.push(fullPath);
        else files.push(fullPath);
      }

      if (files.length > 0) {
        await admin.storage.from(bucket).remove(files);
      }

      for (const sub of subfolders) {
        await deleteFolder(sub);
      }
    }

    await deleteFolder(prefix);

    // 3️⃣ Delete relational rows
    await admin.from("post_comment_views").delete().eq("viewer_user_id", uid);

    await admin.from("follows").delete().or(
      `follower_user_id.eq.${uid},followed_user_id.eq.${uid}`
    );

    await admin.from("post_shares").delete().or(
      `owner_user_id.eq.${uid},recipient_user_id.eq.${uid}`
    );

    await admin.from("post_comments").delete().or(
      `author_user_id.eq.${uid},recipient_user_id.eq.${uid},owner_user_id.eq.${uid}`
    );

    await admin.from("posts").delete().eq("owner_user_id", uid);

    await admin.from("account_directory").delete().eq("user_id", uid);

    // 4️⃣ Delete auth user LAST
    await admin.auth.admin.deleteUser(uid);

    return new Response(JSON.stringify({ success: true }), { status: 200 });

  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500 }
    );
  }
});