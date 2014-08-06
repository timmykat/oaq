class QuestionnairesController < ApplicationController
  before_filter :authenticate_user!
  
  def index
    if current_user.try(:superadmin?)
      @questionnaires = Questionnaire.all
    elsif current_user.is_publisher?
      @questionnaires = Questionnaire.all(:conditions => {:publisher_id => current_user.publisher.id})
    elsif current_user.is_author?
      redirect_to('/') and return
    end    
  end
  
  def show
    @questionnaire = Questionnaire.find(params[:id])
    unless params[:author_user_id].nil?
      @user = User.find(params[:author_user_id])
    else
      unless current_user.try(:superadmin?) || current_user.is_publisher? || current_user.is_librarian?
        @user = current_user  
      end  
    end  
    unless @user.nil?
      profile = Author.first(:conditions => {:email => @user.email, :publisher_id => @questionnaire.publisher.id})
      unless profile.nil?
        profile.user_id = @user.id
        profile.save
        @user.publisher_id = @questionnaire.publisher.id
        @user.save
        @publication = Publication.create(:user_id => @user.id, :author_id => profile.id, :publisher_id => @questionnaire.publisher.id, :questionnaire_id => @questionnaire.id)
      else
        @publication = Publication.create(:user_id => @user.id, :publisher_id => @questionnaire.publisher.id, :questionnaire_id => @questionnaire.id)
      end 
    end 
    
  end
  
  def new
    @questionnaire = Questionnaire.new
    
    @lib_req = FormItem.all(:conditions => {:publisher_id => nil, :required => true})
    @pub_req = FormItem.all(:conditions => {:publisher_id => current_user.publisher.id, :required => true})
  end
  
  def edit
    @questionnaire = Questionnaire.find(params[:id])
    
    @lib_req = FormItem.all(:conditions => {:publisher_id => nil, :required => true})
    @pub_req = FormItem.all(:conditions => {:publisher_id => current_user.publisher.id, :required => true})
    
    unless params[:sort_items].nil?
      redirect_to sort_items_questionnaires_url(:sort_items => params[:sort_items], :id => params[:id])
    end
  end
  
  def create
    params[:questionnaire][:publisher] = Publisher.find_by_name(params[:questionnaire][:publisher])
    
    params[:questionnaire][:form_item_ids] << FormItem.all(:conditions => {:required => true}).collect{|fi| fi.id.to_s}
    params[:questionnaire][:form_item_ids] = params[:questionnaire][:form_item_ids].flatten!.reject(&:empty?).collect{|fi| fi.to_i}
    
    @questionnaire = Questionnaire.new(params[:questionnaire])
    
    respond_to do |format|
      if @questionnaire.save
        format.html { redirect_to questionnaires_url, notice: 'Questionnaire was successfully created.' }
        format.json { render json: @questionnaire, status: :created, questionnaire: @questionnaire }
      else
        format.html { render action: "new" }
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end
  
  def update
    params[:questionnaire][:publisher] = Publisher.find_by_name(params[:questionnaire][:publisher])
    @questionnaire = Questionnaire.find(params[:id])
    
    params[:questionnaire][:form_item_ids] << FormItem.all(:conditions => {:required => true}).collect{|fi| fi.id.to_s}
    params[:questionnaire][:form_item_ids] = params[:questionnaire][:form_item_ids].flatten!.reject(&:empty?).collect{|fi| fi.to_i}
    
    respond_to do |format|
      if @questionnaire.update_attributes(params[:questionnaire])
        format.html { redirect_to edit_questionnaire_url(@questionnaire.id), notice: 'Questionnaire was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end
  
  def destroy
    @questionnaire = Questionnaire.find(params[:id])
    @questionnaire.destroy

    respond_to do |format|
      format.html { redirect_to questionnaires_url, notice: 'Questionnaire was successfully deleted.' }
      format.json { head :no_content }
    end
  end  
  
  def gather_response
    params[:gather_response].each_value do |value|
      if FormItem.find(value["form_item_id"].to_i).field_type == "Date"
        value['response_text'] = Date.strptime(value['response_text'], '%m/%d/%Y')
      end
      if FormItem.find(value["form_item_id"].to_i).field_type == "File"
        value['author_upload'] = value['response_text']
        value['response_text'] = "File Upload"
      end
      response = Response.create(value)
    end  
    
    redirect_to root_url, notice: 'Response was successfully recorded.'
  end  
  
  def choose_authors
    @questionnaire = Questionnaire.find(params[:questionnaire_id].to_i)
    @authors = current_user.my_authors
  end
  
  def send_questionnaire
    @questionnaire = Questionnaire.find(params[:questionnaire_id].to_i)
    @authors = Array.new
    unless params[:emails].nil?
      @authors = params[:emails]
    end  
    unless params[:more_emails].blank?
      @new_authors = params[:more_emails].split(",").each{|e| e.strip!}
    end 
    respond_to do |format|
      unless params[:emails].nil? && params[:more_emails].blank?
        unless params[:emails].nil?
          @authors.collect{|e| e.strip}.each do |email|
            @questionnaire.send_questionnaire_email(email)
          end  
        end
        unless params[:more_emails].blank?
          @new_authors.collect{|e| e.strip}.each do |email|
            @questionnaire.send_new_author_questionnaire_email(email)
          end
        end 
        format.html { redirect_to questionnaires_url, notice: 'Questionnaire was successfully sent.' }
        format.json { head :no_content }
      else
        format.html { redirect_to choose_authors_questionnaires_path(:questionnaire_id => @questionnaire), notice: 'Please select authors.' }
        format.json { head :no_content }
      end
    end
  end
  
  def sort_items
    @sorted_hash = params[:sort_items]
    
    @sorted_hash.each_key do |field_name|
      item = FormItem.first(:conditions => {:field_name => field_name})
      form_item_q = FormItemsQuestionnaires.first(:conditions => {:form_item_id => item.id, :questionnaire_id => params[:id] })

      FormItemsQuestionnaires.update_all(["form_item_position = ?", @sorted_hash[field_name].to_i], ["form_item_id = ? AND questionnaire_id = ?", item.id, params[:id].to_i])

      form_item_q.save
    end
    
    redirect_to edit_questionnaire_url(params[:id]), notice: 'Items sorted.'
  end
end
