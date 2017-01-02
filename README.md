# rails-archiver
**This project is currently in beta.**

This project allows you to archive an entire tree of a model and restore it 
back. This is useful for cases where there is one central "work item"
which has many tangential tables associated with it. Rather than having a policy 
to archive each table after a specific amount of time, or to manually
find all related items and archive them, this will search through the
associations of the model, archive them all at once, and allow to restore them.

You can also use this to back up the full model and restore it, e.g. on
a development machine or another environment. This allows you to easily
"package up" related data.

The intended usage is to leave the actual work item where it is so that
you can actually figure out what's available and how to access the associated
tables - the assumption is that all the associations are what's taking up
the room in your database. You can inherit from the base `Archiver` class
if you want to change this behavior.

# Usage

There are two central classes, `Archiver` and `Unarchiver`. Each of them
take a "Transport" which dictates how to store and retrieve the archive.
A sample which uses the AWS SDK to save the archive to S3 is provided.

    archiver = RailsArchiver::Archiver.new(my_model, 
    :transport => :s3, 
    :delete_records => true)
    
    archiver.transport.configure(
      :bucket_name => 'my_bucket',
      :base_path => '/path/to/directory')
    archiver.archive
    
    unarchiver = RailsArchiver::Unarchiver.new(my_model)
    
## Special attributes

If the model has an attribute called "archived", it will automatically be set
to true when it's been archived, and false once it's been unarchived. In 
addition, if using the S3 transport, it will also look for an attribute
called `archived_s3_key` and set it to the location of the archive.

## Deciding what to archive

By default, the archiver will include all associations which are:
1) dependent -> `destroy` or `delete_all`
2) `has_many` or `has_one`

You can change this behavior by subclassing the archiver class and overriding
the `get_associations` method.

## Compatibility

Currently this project has been tested with Rails 3.0. However, since it uses
fairly basic Rails model methods, it should be compatible with Rails 4 and 5
as well.
