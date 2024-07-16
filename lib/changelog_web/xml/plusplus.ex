defmodule ChangelogWeb.Xml.Plusplus do
  use ChangelogWeb, :verified_routes

  alias Changelog.{ListKit}
  alias ChangelogWeb.{EpisodeView, FeedView, PersonView, TimeView, Xml}
  alias ChangelogWeb.Helpers.SharedHelpers

  @doc """
  Returns a full XML document structure ready to be sent to Xml.generate/1
  """
  def document(podcast, episodes) do
    {
      :rss,
      Xml.podcast_namespaces(),
      [channel(podcast, episodes)]
    }
    |> XmlBuilder.document()
  end

  def channel(podcast, episodes) do
    {
      :channel,
      nil,
      [
        {:title, nil, "Changelog++"},
        {:copyright, nil, "All rights reserved"},
        {:link, nil, "https://changelog.com/++"},
        {:language, nil, "en-us"},
        {:description, nil, "Thank you for subscribing to Changelog++!"},
        {"itunes:author", nil, "Changelog Media"},
        {"itunes:block", nil, "yes"},
        {"itunes:explicit", nil, "no"},
        {"itunes:summary", nil, "Thank you for subscribing to Changelog++!"},
        {"itunes:image", %{href: url(~p"/images/podcasts/plusplus-original.png")}},
        {"itunes:category", nil, Xml.itunes_category()},
        Xml.itunes_sub_category(podcast),
        Enum.map(episodes, fn episode -> episode(podcast, episode) end)
      ]
      |> List.flatten()
      |> ListKit.compact()
    }
  end

  def episode(podcast, episode) do
    {:item, nil,
     [
       {:title, nil, FeedView.episode_title(podcast, episode)},
       {:guid, %{isPermaLink: false}, EpisodeView.guid(episode)},
       {:link, nil, url(~p"/#{episode.podcast.slug}/#{episode.slug}")},
       {:pubDate, nil, TimeView.rss(episode.published_at)},
       {:enclosure, enclosure(episode)},
       {:description, nil, SharedHelpers.md_to_text(episode.summary)},
       {"itunes:episodeType", nil, episode.type},
       {"itunes:image", %{href: EpisodeView.cover_url(episode)}},
       {"itunes:duration", nil, duration(episode)},
       {"itunes:explicit", nil, "no"},
       Enum.map(episode.hosts, fn p -> Xml.person(p, "host") end),
       Enum.map(episode.guests, fn p -> Xml.person(p, "guest") end),
       Xml.transcript(episode),
       chapters(episode),
       Xml.socialize(episode),
       {"content:encoded", nil, show_notes(episode)}
     ]}
  end

  defp duration(episode) do
    t =
      if episode.plusplus_file do
        episode.plusplus_duration
      else
        episode.audio_duration
      end

    TimeView.duration(t)
  end

  defp enclosure(episode) do
    {url, bytes} =
      if episode.plusplus_file do
        {EpisodeView.plusplus_url(episode), episode.plusplus_bytes}
      else
        {EpisodeView.audio_url(episode), episode.audio_bytes}
      end

    %{url: url, length: bytes, type: "audio/mpeg"}
  end

  defp chapters(%{audio_chapters: []}), do: nil

  defp chapters(episode) do
    {chapters, url} =
      if episode.plusplus_file && Enum.any?(episode.plusplus_chapters) do
        {episode.plusplus_chapters,
         url(~p"/#{episode.podcast.slug}/#{episode.slug}/chapters?pp=true")}
      else
        {episode.audio_chapters, url(~p"/#{episode.podcast.slug}/#{episode.slug}/chapters")}
      end

    [
      {"podcast:chapters",
       %{
         url: url,
         type: "application/json+chapters"
       }},
      Xml.Chapters.chapters(chapters, "psc")
    ]
  end

  defp show_notes(episode) do
    participants = EpisodeView.participants(episode)

    data =
      [
        SharedHelpers.md_to_html(episode.summary),
        FeedView.discussion_link(episode),
        show_notes_featuring(participants),
        "<p>Show Notes:</p>",
        "<p>#{SharedHelpers.md_to_html(episode.notes)}</p>",
        ~s(<p>Something missing or broken? <a href="#{EpisodeView.show_notes_source_url(episode)}">PRs welcome!</a></p>)
      ]
      |> ListKit.compact_join("")

    {:cdata, data}
  end

  defp show_notes_featuring([]), do: nil

  defp show_notes_featuring(participants) do
    items =
      Enum.map(participants, fn p ->
        ~s"""
          <li>#{p.name} &ndash; #{PersonView.list_of_links(p)}</li>
        """
      end)

    ["<p>Featuring:</p><ul>", items, "</ul></p>"]
  end
end
