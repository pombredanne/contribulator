class Project < ActiveRecord::Base
  validates :name, :owner, presence: true
  validates :name, uniqueness: { scope: :owner, case_sensitive: false }

  after_create :update_info

  MINIMUM_SCORE = 15

  self.per_page = 50

  scope :good, -> { where('score >= ?', Project::MINIMUM_SCORE) }
  scope :needs_update, -> { where('last_scored <= ? OR last_scored IS NULL', 1.week.ago) }

  def self.languages
    select('DISTINCT main_language').map(&:main_language).compact.sort
  end

  def self.create_from_github_url(url)
    create parse_github_url(url)
  end

  def self.find_from_github_url(url)
    attrs = parse_github_url(url)
    find_by_owner_and_name attrs[:owner], attrs[:name]
  end

  def self.find_by_owner_and_name(owner, name)
    find_by!('lower(owner) = lower(?) AND lower(name) = lower(?)', owner, name)
  end

  def self.parse_github_url(url)
    url.gsub!(/^(((https|http|git)?:\/\/(www\.)?)|git@)github.com(:|\/)/i, '')
    url.gsub!(/(\.git|\/)$/i, '')
    parts = url.split('/')
    { owner: parts[0], name: parts[1] }
  end

  def to_s
    name_with_owner
  end

  def name_with_owner
    "#{owner}/#{name}"
  end

  def github_url
    "https://github.com/#{name_with_owner}"
  end

  def update_info
    update_from_github
    update_score
  end

  def repo_id
    github_id || name_with_owner
  end

  def summary
    calculator.summary
  end

  def github_client
    @client ||= Octokit::Client.new(access_token: ENV['OCTOKIT_TOKEN'])
  end

  def has_issues?
    repo['has_issues']
  end

  private

  def update_from_github
    update_attributes(
    github_id:     repo[:id],
    name:          repo[:name],
    owner:         repo[:owner][:login],
    description:   repo[:description],
    homepage:      format_url(repo[:homepage]),
    fork:          repo[:fork],
    main_language: repo[:language]
    )
  end

  def format_url(url)
    return url if url.blank?
    url[/^https?:\/\//] ? url : "http://#{url}"
  end

  def update_score
    update_attributes score: calculator.score, last_scored: Time.now
  end

  def calculator
    @calculator ||= ScoreCalculator.new(self)
  end

  def repo
    @repo ||= github_client.repo(repo_id)
  end
end
