class Service::GithubIssues < Service
  string :access_token, :update_labels_on_close, :comment_label_prefix
  white_list :update_labels_on_close, :comment_label_prefix

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
    if prefix = data['comment_label_prefix']
      labels = comment.body.scan(/#{prefix}(#{LABEL_REGEX})/).map(&:first)
      update_labels!(labels)
    end
  end

  def receive_issues
    if payload['action'] = 'closed'
      labels = data['update_labels_on_close'].split(/,\s*/)
      update_labels!(labels)
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
