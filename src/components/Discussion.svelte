<script lang="ts">
import { onMount } from "svelte";
import type { User } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";

export let slug: string;
type Comment = {id:string; user_id:string; parent_id:string|null; content:string; created_at:string; deleted_at:string|null; profiles:{display_name:string}|null};
let user:User|null=null;
let comments:Comment[]=[];
let total=0, likes=0, limit=50;
let liked=false, loading=true, busy=false;
let error="", notice="", email="", displayName="", body="";
let reply:Comment|null=null;
let confirmDelete:string|null=null;
let disposed=false;
const googleEnabled=import.meta.env.PUBLIC_GOOGLE_AUTH_ENABLED === "true";

function friendlyError(e:unknown):string {
 const message=e instanceof Error ? e.message : String((e as {message?:string})?.message || e);
 if (/rate|too many|slow_down|tunggu/i.test(message)) return "Terlalu banyak permintaan. Tunggu sebentar lalu coba lagi.";
 if (/email.*not.*allowed|smtp|sending.*email/i.test(message)) return "Email masuk belum bisa dikirim. Silakan coba lagi nanti.";
 if (/JWT|session|authentication/i.test(message)) return "Sesi berakhir. Silakan masuk kembali.";
 if (/fetch|network/i.test(message)) return "Koneksi terputus. Periksa internet lalu coba lagi.";
 return "Permintaan belum berhasil. Coba lagi sebentar, atau muat ulang halaman.";
}
async function load() {
 if (!supabase) {loading=false;return;}
 loading=true; error="";
 try {
  const [c,l,own]=await Promise.all([
   supabase.from("comments").select("id,user_id,parent_id,content,created_at,deleted_at,profiles(display_name)",{count:"exact"}).eq("post_slug",slug).order("created_at").order("id").range(0,limit-1),
   supabase.from("post_likes").select("user_id",{count:"exact",head:true}).eq("post_slug",slug),
   user ? supabase.from("post_likes").select("user_id").eq("post_slug",slug).eq("user_id",user.id).maybeSingle() : Promise.resolve({data:null,error:null}),
  ]);
  if(c.error) throw c.error; if(l.error) throw l.error; if(own.error) throw own.error;
  if(disposed) return;
  comments=c.data as unknown as Comment[]; total=c.count||0; likes=l.count||0; liked=Boolean(own.data);
 } catch(e) {if(!disposed) error=friendlyError(e);} finally {if(!disposed) loading=false;}
}
async function run(action:()=>Promise<void>) {
 if(busy) return; busy=true;error="";notice="";
 try {await action();} catch(e) {error=friendlyError(e);} finally {busy=false;}
}
async function login() {await run(async()=>{
 if(!supabase) return;
 const {error:e}=await supabase.auth.signInWithOtp({email:email.trim(),options:{emailRedirectTo:new URL('/auth/callback/',location.origin).href}});
 if(e) throw e;
 sessionStorage.setItem("returnToPost",`/posts/${slug}/`);
 notice="Tautan masuk sudah dikirim. Buka email di browser ini untuk melanjutkan.";
});}
async function google() {await run(async()=>{
 if(!supabase) return; sessionStorage.setItem("returnToPost",`/posts/${slug}/`);
 const {error:e}=await supabase.auth.signInWithOAuth({provider:"google",options:{redirectTo:new URL('/auth/callback/',location.origin).href}});if(e) throw e;
});}
async function logout() {await run(async()=>{const result=await supabase?.auth.signOut();if(result?.error) throw result.error;user=null;reply=null;await load();});}
async function toggleLike() {await run(async()=>{
 if(!supabase||!user) {notice="Masuk terlebih dahulu untuk menyukai tulisan ini.";return;}
 const result=liked ? await supabase.from("post_likes").delete().eq("post_slug",slug).eq("user_id",user.id) : await supabase.from("post_likes").upsert({post_slug:slug,user_id:user.id},{onConflict:"post_slug,user_id",ignoreDuplicates:true});
 if(result.error) throw result.error;await load();
});}
async function submit() {await run(async()=>{
 if(!supabase||!user||!body.trim()||!displayName.trim()) return;
 const existing=await supabase.from("profiles").select("id").eq("id",user.id).maybeSingle();if(existing.error)throw existing.error;
 const p=existing.data ? await supabase.from("profiles").update({display_name:displayName.trim()}).eq("id",user.id) : await supabase.from("profiles").insert({id:user.id,display_name:displayName.trim()});if(p.error) throw p.error;
 const result=await supabase.from("comments").insert({post_slug:slug,user_id:user.id,content:body.trim(),parent_id:reply ? (reply.parent_id || reply.id) : null});
 if(result.error) throw result.error;
 body="";reply=null;limit=Math.max(limit,total+1);notice="Komentar berhasil dikirim.";await load();
});}
async function remove(id:string) {await run(async()=>{
 if(!supabase) return;
 const {error:e}=await supabase.from("comments").update({content:"",deleted_at:new Date().toISOString()}).eq("id",id).eq("user_id",user!.id);
 if(e) throw e;confirmDelete=null;notice="Komentarmu sudah dihapus.";await load();
});}
function replyTo(c:Comment) {reply=c;document.getElementById("comment-body")?.focus();}
function name(c:Comment) {return c.profiles?.display_name || "Pembaca";}

onMount(()=>{
 if(!supabase){loading=false;return;}
 const client=supabase;
 let generation=0;
 async function updateUser(next:User|null){
  const current=++generation;user=next;
  if(next){const p=await client.from("profiles").select("display_name").eq("id",next.id).maybeSingle();if(current===generation&&!disposed)displayName=p.data?.display_name||"";}
  if(!disposed&&current===generation) await load();
 }
 client.auth.getSession().then(({data,error:e})=>{if(e){error=friendlyError(e);loading=false;}else if(!disposed)void updateUser(data.session?.user||null);});
 const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{setTimeout(()=>{if(!disposed)void updateUser(session?.user||null);},0);});
 return ()=>{disposed=true;subscription.unsubscribe();};
});
</script>

<section class="discussion card-base p-6 md:p-9 mb-4 text-black/90 dark:text-white/90" aria-label="Diskusi pembaca" data-pagefind-ignore>
 <h2 class="text-2xl font-bold mb-4">Ruang diskusi</h2>
 {#if !supabase}<p>Ruang diskusi sedang disiapkan. Silakan kembali lagi nanti.</p>
 {:else}
 <div class="flex flex-wrap gap-4 items-center mb-6">
  <button type="button" class="action" aria-pressed={liked} disabled={busy||loading} on:click={toggleLike}>{liked ? "Disukai" : "Sukai tulisan"} · {likes}</button>
  <p>{total} komentar <span class="text-sm">(termasuk utas yang dihapus)</span></p>
 </div>
 {#if user}
  <div class="flex flex-wrap gap-4 items-center mb-5"><p>Kamu sudah masuk.</p><button type="button" class="text-link" disabled={busy} on:click={logout}>Keluar</button></div>
  <form on:submit|preventDefault={submit} class="grid gap-3 mb-8">
   <label for="comment-name">Nama publik</label><input id="comment-name" bind:value={displayName} required minlength="2" maxlength="50" autocomplete="nickname" disabled={busy}/>
   {#if reply}<div class="flex flex-wrap items-center gap-3"><p>Membalas {name(reply)}</p><button type="button" class="text-link" on:click={()=>reply=null}>Batal membalas</button></div>{/if}
   <label for="comment-body">{reply ? "Balasanmu" : "Komentarmu"}</label><textarea id="comment-body" bind:value={body} required maxlength="3000" rows="4" disabled={busy} placeholder="Bagikan pendapat dengan ramah…"></textarea>
   <p class="text-sm">Nama dan komentarmu akan terlihat publik. Jangan bagikan informasi pribadi.</p>
   <button class="action justify-self-start" disabled={busy||!body.trim()||displayName.trim().length<2}>{busy ? "Menyimpan…" : reply ? "Kirim balasan" : "Kirim komentar"}</button>
  </form>
 {:else}
  <form on:submit|preventDefault={login} class="grid gap-3 mb-8">
   <p>Masuk untuk berkomentar, membalas, dan menyukai tulisan.</p>
   <label for="reader-email">Email</label><input id="reader-email" type="email" bind:value={email} required autocomplete="email" disabled={busy} placeholder="nama@contoh.com"/>
   <button class="action justify-self-start" disabled={busy}>{busy ? "Mengirim…" : "Kirim tautan masuk"}</button>
   {#if googleEnabled}<button type="button" class="action justify-self-start" disabled={busy} on:click={google}>Masuk dengan Google</button>{/if}
   <p class="text-sm">Email digunakan untuk login dan tidak ditampilkan pada komentar.</p>
  </form>
 {/if}
 {#if error}<div role="alert" class="mb-5"><p>{error}</p><button type="button" class="text-link" on:click={load}>Coba muat ulang</button></div>{/if}
 {#if notice}<p role="status" class="mb-5">{notice}</p>{/if}
 {#if loading}<p role="status">Memuat diskusi…</p>{:else if !error && comments.length===0}<p>Belum ada komentar. Jadilah yang pertama memulai percakapan.</p>{/if}
 <div aria-busy={loading}>
 {#each comments.filter(c=>!c.parent_id) as root(root.id)}
  {#each [root,...comments.filter(c=>c.parent_id===root.id)] as c(c.id)}
   <article class:reply={Boolean(c.parent_id)} class="comment py-5 border-t border-[var(--line-divider)]">
    <div class="flex flex-wrap gap-x-3 gap-y-1 items-baseline mb-2"><h3 class="font-bold">{c.deleted_at ? "Komentar dihapus" : name(c)}</h3><time class="text-sm" datetime={c.created_at}>{new Intl.DateTimeFormat("id",{dateStyle:"medium",timeStyle:"short"}).format(new Date(c.created_at))}</time></div>
    <p class="comment-text">{c.deleted_at ? "Komentar ini telah dihapus oleh penulisnya." : c.content}</p>
    {#if user && !c.deleted_at}<div class="flex flex-wrap gap-4 mt-3"><button type="button" class="text-link" disabled={busy} on:click={()=>replyTo(c)}>Balas<span class="sr-only"> {name(c)}</span></button>
     {#if user.id===c.user_id}<button type="button" class="text-link" disabled={busy} on:click={()=>confirmDelete=c.id}>Hapus komentar saya</button>{/if}
    </div>{/if}
    {#if confirmDelete===c.id}<div class="mt-3 flex flex-wrap items-center gap-3"><p>Hapus isi komentar ini? Balasan tetap tersimpan.</p><button type="button" class="action" disabled={busy} on:click={()=>remove(c.id)}>Ya, hapus</button><button type="button" class="text-link" on:click={()=>confirmDelete=null}>Batal</button></div>{/if}
   </article>
  {/each}
 {/each}
 </div>
 {#if comments.length<total}<button type="button" class="action mt-4" disabled={busy||loading} on:click={()=>{limit+=50;void load();}}>Muat lebih banyak komentar</button>{/if}
 {/if}
</section>

<style>
.discussion{overflow-wrap:anywhere}
.discussion input,.discussion textarea{width:100%;min-width:0;border:1px solid var(--line-divider);border-radius:.75rem;background:var(--page-bg);color:inherit;padding:.75rem 1rem;caret-color:var(--primary)}
.discussion input::placeholder,.discussion textarea::placeholder{color:inherit;opacity:.72}
.action{min-height:44px;padding:.65rem 1rem;border-radius:.75rem;background:var(--btn-regular-bg);color:var(--btn-content);font-weight:500}
.action:hover{background:var(--btn-regular-bg-hover)}
button:disabled{opacity:.6;cursor:wait}
.text-link{min-height:44px;text-decoration:underline;text-underline-offset:4px;color:var(--primary)}
:is(button,input,textarea):focus-visible{outline:2px solid var(--primary);outline-offset:3px}
.comment-text{white-space:pre-wrap;line-height:1.7}
.reply{margin-left:clamp(.75rem,3vw,2rem)}
</style>
