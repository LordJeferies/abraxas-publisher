import {
  convertFileSrc,
} from '@tauri-apps/api/core'

import {
  Heart,
  MessageCircle,
  MoreHorizontal,
  Play,
  Send,
  Share2,
  ThumbsUp,
} from 'lucide-react'

import type {
  ContentItem,
  PublicationTarget,
} from '../types'

function Media({
  item,
}: {
  item: ContentItem
}) {
  const media =
    item.media[0]

  if (!media) {
    return (
      <div className="social-media-empty">
        Sin media
      </div>
    )
  }

  const src =
    convertFileSrc(
      media.path,
    )

  if (
    media.kind === 'video'
  ) {
    return (
      <video
        className="social-media"
        src={src}
        controls
        playsInline
      />
    )
  }

  return (
    <img
      className="social-media"
      src={src}
      alt={item.title}
    />
  )
}

export function PlatformPreview({
  item,
  target,
}: {
  item: ContentItem
  target: PublicationTarget
}) {
  const platform =
    target.platform
      .toLowerCase()

  const copy =
    target.copy
    || item.title

  if (
    platform === 'youtube'
  ) {
    const vertical =
      item.contentType
        .toLowerCase()
        .includes('short')
      || item.contentType
        .toLowerCase()
        .includes('reel')

    return (
      <div
        className={
          vertical
            ? 'network-preview youtube short-preview'
            : 'network-preview youtube'
        }
      >
        <div className="network-top">
          YouTube
        </div>

        <div className="youtube-player">
          <Media item={item}/>

          <div className="player-center">
            <Play size={30}/>
          </div>
        </div>

        <div className="youtube-meta">
          <strong>
            {item.title}
          </strong>

          <span>
            JOC · Publicación previa
          </span>

          <div className="network-actions">
            <ThumbsUp size={17}/>
            <Share2 size={17}/>
            <MoreHorizontal size={17}/>
          </div>

          <p>
            {copy}
          </p>
        </div>
      </div>
    )
  }

  if (
    platform === 'linkedin'
  ) {
    return (
      <div className="network-preview linkedin">
        <div className="network-top">
          LinkedIn
        </div>

        <div className="linkedin-author">
          <div className="fake-avatar">
            J
          </div>

          <div>
            <strong>
              Joc López
            </strong>

            <span>
              Ventas · Estrategia
            </span>
          </div>

          <MoreHorizontal size={17}/>
        </div>

        <p className="network-copy">
          {copy}
        </p>

        <Media item={item}/>

        <div className="network-actions spread">
          <span>
            <ThumbsUp size={16}/>
            Recomendar
          </span>

          <span>
            <MessageCircle size={16}/>
            Comentar
          </span>

          <span>
            <Share2 size={16}/>
            Compartir
          </span>
        </div>
      </div>
    )
  }

  if (
    platform === 'tiktok'
  ) {
    return (
      <div className="network-preview tiktok">
        <div className="network-top">
          TikTok · Para ti
        </div>

        <div className="vertical-stage">
          <Media item={item}/>

          <div className="vertical-caption">
            <strong>
              @jocventas
            </strong>

            <p>
              {copy}
            </p>
          </div>

          <div className="vertical-actions">
            <Heart/>
            <MessageCircle/>
            <Share2/>
          </div>
        </div>
      </div>
    )
  }

  if (
    platform === 'facebook'
  ) {
    return (
      <div className="network-preview facebook">
        <div className="network-top">
          Facebook
        </div>

        <div className="linkedin-author">
          <div className="fake-avatar">
            J
          </div>

          <div>
            <strong>
              JOC
            </strong>

            <span>
              Ahora · 🌐
            </span>
          </div>
        </div>

        <p className="network-copy">
          {copy}
        </p>

        <Media item={item}/>

        <div className="network-actions spread">
          <span>
            <ThumbsUp size={16}/>
            Me gusta
          </span>

          <span>
            <MessageCircle size={16}/>
            Comentar
          </span>

          <span>
            <Share2 size={16}/>
            Compartir
          </span>
        </div>
      </div>
    )
  }

  return (
    <div className="network-preview instagram">
      <div className="network-top">
        Instagram
      </div>

      <div className="ig-author">
        <div className="fake-avatar">
          J
        </div>

        <strong>
          jocventas
        </strong>

        <MoreHorizontal size={17}/>
      </div>

      <Media item={item}/>

      <div className="network-actions">
        <Heart size={20}/>
        <MessageCircle size={20}/>
        <Send size={20}/>
      </div>

      <div className="ig-copy">
        <strong>
          jocventas
        </strong>
        {' '}
        {copy}
      </div>

      {
        item.media.length > 1
        && (
          <div className="carousel-dots">
            {
              item.media.map(
                (_, index) => (
                  <span
                    key={index}
                    className={
                      index === 0
                        ? 'active'
                        : ''
                    }
                  />
                ),
              )
            }
          </div>
        )
      }
    </div>
  )
}
