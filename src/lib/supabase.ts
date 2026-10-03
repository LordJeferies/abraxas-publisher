import {
  createClient,
  type RealtimeChannel,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js'

const url =
  import.meta.env
    .VITE_SUPABASE_URL
  || ''

const key =
  import.meta.env
    .VITE_SUPABASE_PUBLISHABLE_KEY
  || import.meta.env
    .VITE_SUPABASE_ANON_KEY
  || ''

let client:
  SupabaseClient | null =
    null

let channel:
  RealtimeChannel | null =
    null

export const PUBLISHER_WORKSPACE =
  'abraxas-publisher'

export function supabaseConfigured() {
  return Boolean(
    url && key,
  )
}

export function supabaseClient() {
  if (
    !supabaseConfigured()
  ) {
    return null
  }

  if (!client) {
    client =
      createClient(
        url,
        key,
        {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
          },
        },
      )
  }

  return client
}

export async function cloudUser():
  Promise<User | null> {
  const supabase =
    supabaseClient()

  if (!supabase) {
    return null
  }

  const {
    data,
  } =
    await supabase
      .auth
      .getSession()

  return (
    data.session?.user
    || null
  )
}

export async function cloudSignIn(
  email: string,
  password: string,
) {
  const supabase =
    supabaseClient()

  if (!supabase) {
    throw new Error(
      'Supabase no está configurado.',
    )
  }

  const {
    data,
    error,
  } =
    await supabase
      .auth
      .signInWithPassword({
        email,
        password,
      })

  if (error) {
    throw error
  }

  return data.session
}

export async function cloudSignUp(
  email: string,
  password: string,
) {
  const supabase =
    supabaseClient()

  if (!supabase) {
    throw new Error(
      'Supabase no está configurado.',
    )
  }

  const {
    data,
    error,
  } =
    await supabase
      .auth
      .signUp({
        email,
        password,
      })

  if (error) {
    throw error
  }

  return data
}

export async function cloudSignOut() {
  const supabase =
    supabaseClient()

  if (!supabase) {
    return
  }

  if (channel) {
    await supabase
      .removeChannel(
        channel,
      )

    channel = null
  }

  await supabase
    .auth
    .signOut()
}

export function setPublisherChannel(
  value:
    RealtimeChannel | null,
) {
  channel = value
}

export function getPublisherChannel() {
  return channel
}
