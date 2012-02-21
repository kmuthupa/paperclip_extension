module Paperclip
  module Storage
    # This extends Paperclip to use Common Services document storage APIs
    module Cws
      def self.extended base
      end

      def exists?(style_name = default_style)
        asset_content(style_name) ? true : false
      end
      
      def asset_content style_name = default_style
        return if instance.attached_ids.blank?
        begin
          doc_content = CommonServices::DocumentUploadService.read_document(instance.attached_ids[style_name], patient_id_for_attachment)
          doc_content.nil? ? nil : String.from_java_bytes(doc_content.contents)
        rescue
          nil
        end
      end

      def to_file style_name = default_style
        raise 'to_file not implemented for paperclip extension utilising cws document storage'
      end

      def flush_writes 
        return if instance.attached_ids && !instance.attached_ids.values.empty?
        instance.attached_ids = {}
        @queued_for_write.each do |style_name, file|
          doc_options = {}
          doc_options[:file_name] = original_filename
          doc_options[:content_type] = content_type
          doc_options[:asset_name] = instance.asset_name
          doc_options[:asset_type] = instance.asset_type ? instance.asset_type.gsub('-', '_').upcase : ''
          doc_options[:enterprise_id] = instance.enterprise_id
          doc_options[:patient_id] = patient_id_for_attachment
          doc_options[:user_id] = instance.enterprise_site_user_id ? instance.enterprise_site_user_id : 1 #TODO:(needs to be -1, CS client blowing up right now if -1 is passed..)
          doc_options[:state] = instance.state
          doc_options[:content] = file.read
          file.close
          begin
            doc = CommonServices::DocumentUploadService.write_document(doc_options)
            instance.attached_ids[style_name] = doc.id
            instance.send(:update_without_callbacks) #save the attached ids to DB
          rescue
            instance.destroy if !instance.frozen?
            instance.invalid_asset = true
          end     
        end
        @queued_for_write = {}
      end

      def flush_deletes
        @queued_for_delete.each do |a|  
          begin 
            CommonServices::DocumentUploadService.delete_document(a, patient_id_for_attachment)
          rescue
          end
        end
        @queued_for_delete = []
      end

      def queue_existing_for_delete 
        @queued_for_delete = instance.try(:attached_ids).try(:values) || []
        instance_write(:attached_ids, nil)
        instance_write(:file_name, nil)
        instance_write(:content_type, nil)
        instance_write(:file_size, nil)
        instance_write(:updated_at, nil)
      end

      private 

      def patient_id_for_attachment
        ActiveRecord::Base.view_workaround do
          instance.patient_id ? instance.patient_id : 1 #TODO:(needs to be -1, CS client blowing up right now if -1 is passed..)
        end
      end
    end

  end

end

