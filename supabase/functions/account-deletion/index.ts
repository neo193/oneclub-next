const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const env=(name:string)=>{const value=Deno.env.get(name);if(!value)throw new Error(`Missing server secret: ${name}`);return value;};
const url=env("SUPABASE_URL"),serviceKey=env("SUPABASE_SERVICE_ROLE_KEY"),anonKey=env("SUPABASE_ANON_KEY");
async function request(path:string,key:string,authorization:string,options:RequestInit={}){const response=await fetch(`${url}${path}`,{...options,headers:{apikey:key,Authorization:authorization,"Content-Type":"application/json",...(options.headers||{})}});const data=await response.json().catch(()=>null);if(!response.ok)throw new Error(data?.msg||data?.message||data?.error_description||"Account deletion request failed");return data;}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({message:"Method not allowed"},405);
  try{
    const authorization=req.headers.get("authorization");if(!authorization)throw new Error("Sign in required");
    const user=await request("/auth/v1/user",anonKey,authorization);
    const input=await req.json().catch(()=>({}));const password=String(input.password||"");
    if(!user?.id||!user?.email)throw new Error("Session is invalid");
    if(password.length<8)throw new Error("Enter your current password");
    await request("/auth/v1/token?grant_type=password",anonKey,`Bearer ${anonKey}`,{method:"POST",body:JSON.stringify({email:user.email,password})});
    const eligibility=await request("/rest/v1/rpc/get_account_deletion_eligibility",anonKey,authorization,{method:"POST",body:"{}"});
    if(!eligibility?.allowed)throw new Error(eligibility?.block_reason==="pending_refunds"?"Pending refunds must be resolved first":"Upcoming bookings must be resolved first");
    const prepared=await request("/rest/v1/rpc/finalize_member_account_anonymization",serviceKey,`Bearer ${serviceKey}`,{method:"POST",body:JSON.stringify({p_member_id:user.id,p_original_email:user.email})});
    return json({deleted:true,deletion_reference:prepared?.deletion_reference});
  }catch(error){const message=error instanceof Error?error.message:"Account deletion failed";console.error("Account deletion failed",{message});return json({message},400);}
});
