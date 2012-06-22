class Service::GithubIssues < Service
  UPDATE_LABELS = [:closed, :reopened, :opened, :commented].map do |action|
    "update_labels_when_#{action}".to_sym
  end

  string :access_token, :comment_label_prefix, *UPDATE_LABELS
  white_list :comment_label_prefix, *UPDATE_LABELS

  LABEL_REGEX = /\"[^\"]+\"|[-\w]+/

  self.title = 'Github:issues'

  def url
    @url ||= begin
      repo_url  = payload['repository']['url']
      issue_num = payload['issue']['number']
      token     = data['access_token']
      "#{repo_url}/issues/#{issue_num}?access_token=#{token}"
    end
  end

  def receive_issue_comment
    update_labels!(action_labels(:commented) + comment_labels)
  end

  def receive_issues
    update_labels!(action_labels)
  end

  def action_labels(action = payload['action'])
    if update_labels = data["update_labels_when_#{action}"]
      update_labels.split(/,\s*/)
    else
      []
    end
  end

  def comment_labels
    if prefix = data['comment_label_prefix']
      comment.body.scan(/#{prefix}(#{LABEL_REGEX})/).map(&:first)
    else
      []
    end
  end

  def update_labels!(labels)
    if labels.any?
      old_labels = issue.labels.map {|l| l['name']}.to_set
      new_labels = old_labels.dup

      labels.each do |label|
        if label.start_with?('-')
          new_labels.delete(label[1..-1])
        else
          new_labels << label
        end
      end

      if old_labels != new_labels
        http_method(:patch, url, {:labels => new_labels}.to_json)
      end
    end
  end
end
